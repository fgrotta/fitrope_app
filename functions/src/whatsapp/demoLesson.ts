// Regole del destinatario e invio di un WhatsApp "lezione demo" via Make.
//
// Qui NON si decide chi è un utente di prova: lo decide il chiamante con
// `isTrialUser` (enrollment/trial.ts) — l'iscrizione per la conferma, il cron
// per il promemoria. Questo modulo verifica solo che la coppia utente/corso sia
// notificabile (utente attivo, corso futuro, nome e cellulare validi, allowlist
// di staging) e gestisce claim, POST ed esito nel registro (sendLog.ts).

import { logger } from "firebase-functions";
import type { Firestore } from "firebase-admin/firestore";
import { isWhatsappRecipientAllowed } from "./environment";
import { PostResult } from "./makeClient";
import {
  DemoLessonPayload,
  DemoWebhookKind,
  buildDemoLessonPayload,
  buildNome,
  sanitizeTemplateParam,
} from "./payload";
import { normalizePhoneE164 } from "./phone";
import { SendLogOutcome, claimSend, markSendOutcome, wasNotifiedToday } from "./sendLog";

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

/**
 * Verifica che la coppia utente/corso vada notificata. Pura.
 *
 * `reminderEnabled` governa il promemoria ma non la conferma: un admin che
 * disattiva i promemoria di un corso non chiede di non confermare le iscrizioni.
 */
export function checkRecipient(
  kind: DemoWebhookKind,
  user: DemoUser,
  course: DemoCourse,
  nowMillis: number,
  env: NodeJS.ProcessEnv
): RecipientCheck {
  if (!user.isActive) return { ok: false, reason: "inactive" };
  if (course.startAtMillis === null) return { ok: false, reason: "course_without_date" };
  if (course.startAtMillis <= nowMillis) return { ok: false, reason: "course_in_past" };
  if (kind === "reminder" && !course.reminderEnabled) {
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
  apiKey: string;
  post: (url: string, apiKey: string, payload: DemoLessonPayload) => Promise<PostResult>;
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
 *
 * `noticeDayMillis` è il giorno di riferimento per sopprimere il promemoria
 * dopo una conferma: per il cron l'istante schedulato (stabile anche nei retry),
 * per la conferma l'ora corrente.
 */
export async function dispatchDemoLesson(
  deps: WhatsappDeps,
  kind: DemoWebhookKind,
  user: DemoUser,
  course: DemoCourse,
  noticeDayMillis: number = deps.nowMillis
): Promise<SendOutcome> {
  const check = checkRecipient(kind, user, course, deps.nowMillis, deps.env);
  if (!check.ok) return { sent: false, reason: check.reason };

  const ids = { kind, userId: user.uid, courseId: course.uid };

  if (kind === "reminder" && (await wasNotifiedToday(deps.db, user.uid, course.uid, noticeDayMillis))) {
    return { sent: false, reason: "already_notified_today" };
  }

  const claim = await claimSend(deps.db, kind, user.uid, course.uid, deps.nowMillis);
  if (claim === "sent") return { sent: false, reason: "already_sent" };
  if (claim === "needs_review") return { sent: false, failed: true, reason: "needs_review" };

  const payload = buildDemoLessonPayload({
    kind,
    nome: check.nome,
    corso: check.corso,
    phoneE164: check.phoneE164,
    startAtMillis: check.startAtMillis,
  });
  const wait = deps.wait ?? defaultWait;

  let result: PostResult = { ok: false, status: 0 };
  for (let attempt = 0; ; attempt++) {
    try {
      result = await deps.post(deps.webhookUrl, deps.apiKey, payload);
    } catch (err) {
      // postToMake non lancia: qui arriva solo un post iniettato difettoso. Il
      // messaggio del chiamante può contenere URL o chiave: non lo logghiamo.
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
    await markSendOutcome(deps.db, kind, user.uid, course.uid, outcome, result.status);
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

// ──────────────────────────────────────────────
//  Conferma alla prenotazione (da subscribeToCourseHandler)
// ──────────────────────────────────────────────

/** Legge un corso per id del documento, con fallback sul campo `uid`. */
async function findCourse(db: Firestore, courseId: string): Promise<DemoCourse | null> {
  const direct = await db.collection("courses").doc(courseId).get();
  if (direct.exists) {
    return mapDemoCourseDoc({ id: courseId, data: () => direct.data() });
  }
  // Alcuni documenti storici hanno un `uid` diverso dall'id del documento.
  const query = await db.collection("courses").where("uid", "==", courseId).limit(1).get();
  const doc = query.docs[0];
  return doc ? mapDemoCourseDoc({ id: doc.id, data: () => doc.data() }) : null;
}

/**
 * WhatsApp di conferma dopo un'iscrizione già committata. Rilegge utente e
 * corso: la decisione "utente di prova" l'ha già presa subscribeToCourseHandler.
 * Best-effort: gli scarti tornano come esito, gli errori Firestore come rifiuto
 * che EnrollmentDeps ignora.
 */
export async function notifyDemoLessonBooked(
  deps: WhatsappDeps,
  userId: string,
  courseId: string
): Promise<SendOutcome> {
  const userSnap = await deps.db.collection("users").doc(userId).get();
  const course = await findCourse(deps.db, courseId);

  let outcome: SendOutcome;
  if (!userSnap.exists) {
    outcome = { sent: false, reason: "user_not_found" };
  } else if (course === null) {
    outcome = { sent: false, reason: "course_not_found" };
  } else {
    const user = mapDemoUserDoc({ id: userId, data: () => userSnap.data() });
    outcome = await dispatchDemoLesson(deps, "booked", user, course);
  }

  if (!outcome.sent) {
    logger.info("Conferma WhatsApp non inviata", { userId, courseId, reason: outcome.reason });
  }
  return outcome;
}
