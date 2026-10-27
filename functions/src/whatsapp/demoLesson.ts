// Regole del destinatario e invio del WhatsApp di promemoria "lezione demo"
// via Make.
//
// Qui NON si decide chi è un utente di prova: lo decide il cron con
// `isTrialUser` (enrollment/trial.ts). Questo modulo verifica solo che la coppia utente/corso sia
// notificabile (utente attivo, corso futuro, nome e cellulare validi, allowlist
// di staging) e gestisce claim, POST ed esito nel registro (sendLog.ts).

import { logger } from "firebase-functions";
import type { Firestore } from "firebase-admin/firestore";
import { isWhatsappRecipientAllowed } from "./environment";
import { PostResult } from "./makeClient";
import {
  DemoLessonPayload,
  buildDemoLessonPayload,
  buildNome,
  sanitizeTemplateParam,
} from "./payload";
import { normalizePhoneE164 } from "./phone";
import { SendLogOutcome, claimSend, markSendOutcome } from "./sendLog";

// ──────────────────────────────────────────────
//  Mapping dei documenti Firestore
// ──────────────────────────────────────────────

interface DocLike {
  id: string;
  data: () => Record<string, unknown> | undefined;
}

export interface DemoUser {
  uid: string;
  name: string;
  lastName: string;
  numeroTelefono: string | null;
  isActive: boolean;
  courses: string[];
}

export interface DemoCourse {
  /** Valore con cui il corso compare in `users/{uid}.courses`. */
  uid: string;
  /** Id del documento, che su record storici può differire da `uid`. */
  docId: string;
  name: string;
  startAtMillis: number | null;
  reminderEnabled: boolean;
}

function toMillisOrNull(value: unknown): number | null {
  const maybe = value as { toMillis?: () => number } | null;
  if (maybe && typeof maybe.toMillis === "function") return maybe.toMillis();
  return null;
}

export function mapDemoUserDoc(doc: DocLike): DemoUser {
  const data = doc.data() ?? {};
  return {
    uid: (data.uid as string | undefined) ?? doc.id,
    name: (data.name as string | undefined) ?? "",
    lastName: (data.lastName as string | undefined) ?? "",
    numeroTelefono: (data.numeroTelefono as string | undefined) ?? null,
    isActive: data.isActive !== false,
    courses: Array.isArray(data.courses) ? (data.courses as unknown[]).map(String) : [],
  };
}

export function mapDemoCourseDoc(doc: DocLike): DemoCourse {
  const data = doc.data() ?? {};
  return {
    // Course.fromJson lato Flutter fa `uid ?? id`: stesso fallback, perché in
    // passato sono esistiti documenti senza `uid`.
    uid: (data.uid as string | undefined) ?? (data.id as string | undefined) ?? doc.id,
    docId: doc.id,
    name: (data.name as string | undefined) ?? "",
    startAtMillis: toMillisOrNull(data.startDate),
    reminderEnabled: data.reminderEnabled !== false,
  };
}

// ──────────────────────────────────────────────
//  Selezione del destinatario
// ──────────────────────────────────────────────

export type RecipientCheck =
  | { ok: true; nome: string; corso: string; phoneE164: string; startAtMillis: number }
  | { ok: false; reason: string };

/** Verifica che la coppia utente/corso vada notificata. Pura. */
export function checkRecipient(
  user: DemoUser,
  course: DemoCourse,
  nowMillis: number,
  env: NodeJS.ProcessEnv
): RecipientCheck {
  if (!user.isActive) return { ok: false, reason: "inactive" };
  if (course.startAtMillis === null) return { ok: false, reason: "course_without_date" };
  if (course.startAtMillis <= nowMillis) return { ok: false, reason: "course_in_past" };
  if (!course.reminderEnabled) {
    return { ok: false, reason: "reminder_disabled" };
  }

  const nome = buildNome(user.name, user.lastName);
  if (nome === "") return { ok: false, reason: "no_name" };

  const corso = sanitizeTemplateParam(course.name);
  if (corso === "") return { ok: false, reason: "no_course_name" };

  const phone = normalizePhoneE164(user.numeroTelefono);
  if (phone.e164 === null) {
    const reason = phone.reason;
    return {
      ok: false,
      reason: reason === undefined || reason === "empty" || reason === "placeholder" ? "no_phone" : reason,
    };
  }
  if (!phone.likelyMobile) return { ok: false, reason: "not_mobile" };
  if (!isWhatsappRecipientAllowed(phone.e164, env)) {
    return { ok: false, reason: "not_in_staging_allowlist" };
  }

  return { ok: true, nome, corso, phoneE164: phone.e164, startAtMillis: course.startAtMillis };
}

// ──────────────────────────────────────────────
//  Invio
// ──────────────────────────────────────────────

export interface WhatsappDeps {
  db: Firestore;
  webhookUrl: string;
  post: (url: string, payload: DemoLessonPayload) => Promise<PostResult>;
  nowMillis: number;
  env: NodeJS.ProcessEnv;
  /** Attesa tra i tentativi su HTTP 429; iniettabile per i test. */
  wait?: (ms: number) => Promise<void>;
}

export interface SendOutcome {
  sent: boolean;
  reason?: string;
  /** `true` se l'invio è stato tentato o è da verificare (≠ scartato a monte). */
  failed?: boolean;
}

/** Attese prima del 2° e del 3° tentativo su HTTP 429. */
const RATE_LIMIT_RETRY_DELAYS_MS = [250, 1000];

const defaultWait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** 2xx → sent; 0 (nessuna risposta) o 5xx → unknown; altri 4xx → rejected. */
function classify(result: PostResult): SendLogOutcome {
  if (result.ok) return "sent";
  if (result.status === 0 || result.status >= 500) return "unknown";
  return "rejected";
}

/**
 * Applica le guardie, prenota l'invio e chiama il webhook.
 *
 * Nessun reinvio automatico degli esiti incerti (timeout, rete, 5xx, crash dopo
 * il claim): Make potrebbe aver già accettato il messaggio. Solo HTTP 429 viene
 * ritentato, al massimo due volte sotto lo stesso claim.
 */
export async function dispatchDemoLesson(
  deps: WhatsappDeps,
  user: DemoUser,
  course: DemoCourse
): Promise<SendOutcome> {
  const check = checkRecipient(user, course, deps.nowMillis, deps.env);
  if (!check.ok) return { sent: false, reason: check.reason };

  const ids = { userId: user.uid, courseId: course.uid };

  const claim = await claimSend(deps.db, user.uid, course.uid, deps.nowMillis);
  if (claim === "sent") return { sent: false, reason: "already_sent" };
  if (claim === "needs_review") return { sent: false, failed: true, reason: "needs_review" };

  const payload = buildDemoLessonPayload({
    nome: check.nome,
    corso: check.corso,
    phoneE164: check.phoneE164,
    startAtMillis: check.startAtMillis,
  });
  const wait = deps.wait ?? defaultWait;

  let result: PostResult = { ok: false, status: 0 };
  for (let attempt = 0; ; attempt++) {
    try {
      result = await deps.post(deps.webhookUrl, payload);
    } catch (err) {
      // postToMake non lancia: qui arriva solo un post iniettato difettoso. Il
      // messaggio del chiamante può contenere l'URL: non lo logghiamo.
      logger.error("Invio WhatsApp: eccezione durante la POST", {
        ...ids,
        errorType: err instanceof Error ? err.name : typeof err,
      });
      result = { ok: false, status: 0 };
    }
    if (result.status !== 429 || attempt >= RATE_LIMIT_RETRY_DELAYS_MS.length) break;
    await wait(RATE_LIMIT_RETRY_DELAYS_MS[attempt]);
  }

  const outcome = classify(result);
  try {
    await markSendOutcome(deps.db, user.uid, course.uid, outcome, result.status);
  } catch (err) {
    logger.error("Esito WhatsApp non registrato: claim pending, verificare in Make", {
      ...ids,
      outcome,
      status: result.status,
      error: err instanceof Error ? err.message : String(err),
    });
    return { sent: false, failed: true, reason: "needs_review" };
  }

  if (outcome === "sent") return { sent: true };
  logger.error("Invio WhatsApp non riuscito", { ...ids, outcome, status: result.status });
  return { sent: false, failed: true, reason: `${outcome}_${result.status}` };
}
