// ──────────────────────────────────────────────
//  Integrazione webhook verso Make — reminder WhatsApp lezioni demo
//
//  Due eventi verso un unico Custom webhook Make, che poi invia il messaggio
//  WhatsApp tramite un template approvato da Meta:
//    - "conferma"    → subito, quando un utente ABBONAMENTO_PROVA si iscrive;
//    - "promemoria"  → dal cron delle 19:00, per le lezioni del giorno dopo.
//
//  Il body è quello che lo scenario Make si aspetta già (chiavi in italiano):
//  aggiungere o rinominare un campo richiede un "Redetermine data structure"
//  lato Make, altrimenti il campo non è selezionabile nei moduli a valle.
//
//  La chiave di autenticazione viaggia nell'header `Demo-Reminder`, non nel
//  body: così non finisce nella struttura dati appresa dal webhook né nella
//  cronologia delle esecuzioni dello scenario.
// ──────────────────────────────────────────────

import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { Firestore, Timestamp } from "firebase-admin/firestore";

import { HandlerRequest } from "./handler";
import {
  formatGiorno,
  formatOrario,
  isSameRomeDay,
  romeDayWindow,
  romeDayWindowPadded,
} from "./romeTime";

/** Header su cui lo scenario Make filtra le richieste. */
export const MAKE_AUTH_HEADER = "Demo-Reminder";

/** Tipologia di iscrizione che identifica una lezione di prova. */
export const TIPOLOGIA_PROVA = "ABBONAMENTO_PROVA";

export type DemoWebhookKind = "booked" | "reminder";

/** Valore del campo `tipo` nel body, su cui il Router di Make instrada. */
export const TIPO_BY_KIND: Record<DemoWebhookKind, string> = {
  booked: "conferma",
  reminder: "promemoria",
};

/** Body atteso dal webhook Make. Nessuna chiave in più, nessuna in meno. */
export interface DemoLessonPayload {
  tipo: string;
  nome: string;
  numero_di_telefono: string;
  corso: string;
  giorno: string;
  orario: string;
}

export interface NormalizedPhone {
  /** Numero in formato E.164 (con il `+`), o `null` se non utilizzabile. */
  e164: string | null;
  /** Sole cifre, senza `+`. */
  digits: string | null;
  /** `false` se il numero non è (probabilmente) raggiungibile su WhatsApp. */
  likelyMobile: boolean;
  /** Motivo dello scarto, per i log. */
  reason?: string;
}

// ──────────────────────────────────────────────
//  Normalizzazione del numero di telefono
// ──────────────────────────────────────────────

/** Lunghezza minima e massima di un numero E.164. */
const E164_MIN = 8;
const E164_MAX = 15;

/** Lunghezza ammessa per un numero nazionale italiano (mobile o fisso). */
const IT_NATIONAL_MIN = 6;
const IT_NATIONAL_MAX = 11;

/**
 * Porta il `numeroTelefono` di Firestore in E.164.
 *
 * Il dato in ingresso è di norma pulito — le tre schermate che lo scrivono
 * validano 10 cifre numeriche senza prefisso — ma i record creati da console,
 * import o versioni precedenti possono contenere separatori, prefissi
 * internazionali, numeri fissi o addirittura due numeri nello stesso campo.
 */
export function normalizePhoneE164(raw: string | null | undefined): NormalizedPhone {
  const nope = (reason: string): NormalizedPhone => ({
    e164: null,
    digits: null,
    likelyMobile: false,
    reason,
  });

  if (raw === null || raw === undefined) return nope("empty");

  // \s non copre l'NBSP in tutte le versioni di JS: lo normalizzo a mano.
  const trimmed = raw.replace(/[  ]/g, " ").trim();
  if (trimmed === "") return nope("empty");
  // '-' è il placeholder già usato per le email mancanti (vedi handler.ts).
  if (trimmed === "-") return nope("placeholder");

  const hasPlus = trimmed.startsWith("+");
  let digits = trimmed.replace(/\D/g, "");
  if (digits === "") return nope("not_numeric");

  // Prefisso internazionale scritto come 00 anziché +.
  let international = hasPlus;
  if (!international && digits.startsWith("00") && digits.length >= 12) {
    digits = digits.slice(2);
    international = true;
  }

  if (international) {
    if (digits.length < E164_MIN) return nope("too_short");
    if (digits.length > E164_MAX) return nope("too_long");
    const national = digits.startsWith("39") ? digits.slice(2) : null;
    return {
      e164: `+${digits}`,
      digits,
      // Fuori dall'Italia non possiamo dedurre nulla dal prefisso: meglio
      // provare a inviare che scartare in silenzio un destinatario valido.
      likelyMobile: national === null ? true : isItalianMobile(national),
    };
  }

  // Numero nazionale italiano. Attenzione: un `39` iniziale su 10 cifre NON è
  // il prefisso paese ma l'inizio del numero (es. 3931234567).
  const national =
    digits.startsWith("39") && digits.length >= 12 ? digits.slice(2) : digits;

  if (national.length < IT_NATIONAL_MIN) return nope("too_short");
  if (national.length > IT_NATIONAL_MAX) return nope("too_long");

  const full = `39${national}`;
  return {
    e164: `+${full}`,
    digits: full,
    likelyMobile: isItalianMobile(national),
  };
}

/** I mobili italiani iniziano per 3 e hanno 9 o 10 cifre. */
function isItalianMobile(national: string): boolean {
  return national.startsWith("3") && national.length >= 9 && national.length <= 10;
}

// ──────────────────────────────────────────────
//  Costruzione del payload
// ──────────────────────────────────────────────

/**
 * I parametri di un template WhatsApp non ammettono newline, tab né 4+ spazi
 * consecutivi: Meta rifiuta il messaggio. Collasso tutti gli spazi in uno.
 */
export function sanitizeTemplateParam(value: string | null | undefined): string {
  if (value === null || value === undefined) return "";
  return value.replace(/\s+/g, " ").trim();
}

/** `"Mario Rossi"` da nome e cognome, tollerando l'assenza del cognome. */
export function buildNome(name: string | null | undefined, lastName: string | null | undefined): string {
  return sanitizeTemplateParam(`${name ?? ""} ${lastName ?? ""}`);
}

export interface BuildPayloadArgs {
  kind: DemoWebhookKind;
  nome: string;
  phoneE164: string;
  corso: string;
  startAt: Date;
  /** Override della data formattata: usato solo dalla callable di debug. */
  giorno?: string;
  /** Override dell'orario formattato: usato solo dalla callable di debug. */
  orario?: string;
}

/**
 * Costruisce il body per Make. Tutti i campi sono obbligatori e non vuoti: i
 * chiamanti scartano a monte gli utenti privi di nome o telefono, quindi un
 * campo vuoto qui è un bug e non un caso da gestire a runtime.
 */
export function buildDemoLessonPayload(args: BuildPayloadArgs): DemoLessonPayload {
  const payload: DemoLessonPayload = {
    tipo: TIPO_BY_KIND[args.kind],
    nome: sanitizeTemplateParam(args.nome),
    numero_di_telefono: args.phoneE164,
    corso: sanitizeTemplateParam(args.corso),
    giorno: sanitizeTemplateParam(args.giorno) || formatGiorno(args.startAt),
    orario: sanitizeTemplateParam(args.orario) || formatOrario(args.startAt),
  };

  for (const [key, value] of Object.entries(payload)) {
    if (typeof value !== "string" || value === "") {
      throw new Error(`Campo "${key}" vuoto nel payload Make: i parametri del template WhatsApp non ammettono valori vuoti`);
    }
  }

  return payload;
}

// ──────────────────────────────────────────────
//  Chiamata al webhook
// ──────────────────────────────────────────────

/**
 * Il webhook Make risponde subito con `Accepted`: senza un timeout esplicito
 * (undici in Node non ne ha uno breve di default) uno scenario appeso
 * bloccherebbe callable e cron per minuti.
 */
const DEFAULT_TIMEOUT_MS = 10_000;

export interface PostResult {
  ok: boolean;
  /** Status HTTP, `0` se la richiesta non è nemmeno partita. */
  status: number;
}

/** Host dell'URL, per i log: mai l'URL completo, che contiene il token del webhook. */
function safeHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return "unknown";
  }
}

/** Rimuove URL e chiave da un messaggio d'errore prima di loggarlo. */
function scrubSecrets(message: string, secrets: string[]): string {
  let out = message;
  for (const secret of secrets) {
    if (secret) out = out.split(secret).join("[redacted]");
  }
  return out;
}

/**
 * POST del payload al Custom webhook Make. Non lancia mai: gli errori sono
 * esiti normali che il cron deve poter attraversare senza interrompere il run.
 *
 * La risposta non viene deserializzata: Make risponde con il testo `Accepted`,
 * non con JSON, e comunque non ci serve nulla del corpo.
 */
export async function postToMake(
  url: string,
  apiKey: string,
  payload: DemoLessonPayload,
  opts: { timeoutMs?: number } = {}
): Promise<PostResult> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const host = safeHost(url);

  let response: Awaited<ReturnType<typeof fetch>>;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [MAKE_AUTH_HEADER]: apiKey,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    logger.error("Chiamata al webhook Make fallita", {
      host,
      tipo: payload.tipo,
      error: scrubSecrets(err instanceof Error ? err.message : String(err), [url, apiKey]),
    });
    return { ok: false, status: 0 };
  }

  if (!response.ok) {
    logger.error("Webhook Make ha risposto con errore", {
      host,
      status: response.status,
      tipo: payload.tipo,
    });
    return { ok: false, status: response.status };
  }

  logger.info("Webhook Make chiamato", { host, status: response.status, tipo: payload.tipo });
  return { ok: true, status: response.status };
}

// ──────────────────────────────────────────────
//  Log degli invii (idempotenza)
// ──────────────────────────────────────────────

/**
 * Ogni messaggio WhatsApp è a pagamento, quindi teniamo traccia di cosa è già
 * partito. Il documento contiene solo identificativi: niente telefono e niente
 * email, perché le security rules non sono versionate in questo repo e non
 * sappiamo con certezza cosa i client possano leggere.
 */
export const DEMO_LOG_COLLECTION = "demoLessonWebhookLog";

/**
 * `(kind, userId, courseId)` è già una chiave univoca: un corso ha una sola
 * data, quindi non serve (e non conviene) infilare il giorno nell'id — se un
 * admin spostasse la lezione, un id datato farebbe partire un secondo invio.
 */
export function demoLogDocId(
  kind: DemoWebhookKind,
  userId: string,
  courseId: string
): string {
  if (!userId || !courseId || /[/]/.test(userId) || /[/]/.test(courseId)) {
    throw new Error("userId/courseId non validi per un id di documento Firestore");
  }
  return `${kind}_${userId}_${courseId}`;
}

function isAlreadyExists(err: unknown): boolean {
  const code = (err as { code?: number | string } | null)?.code;
  if (code === 6 || code === "6" || code === "already-exists") return true;
  const message = err instanceof Error ? err.message : String(err);
  return /already exists/i.test(message);
}

function toDate(value: unknown): Date | null {
  if (value instanceof Date) return value;
  const maybe = value as { toDate?: () => Date } | null;
  if (maybe && typeof maybe.toDate === "function") return maybe.toDate();
  return null;
}

/**
 * Prenota l'invio *prima* della POST: `create()` è atomico, quindi protegge
 * anche da due run concorrenti. Ritorna `false` se il messaggio era già partito.
 */
export async function claimSend(
  db: Firestore,
  kind: DemoWebhookKind,
  userId: string,
  courseId: string,
  now: Date
): Promise<boolean> {
  const ref = db.collection(DEMO_LOG_COLLECTION).doc(demoLogDocId(kind, userId, courseId));
  try {
    await ref.create({
      kind,
      userId,
      courseId,
      sentAt: Timestamp.fromDate(now),
      ok: false,
    });
    return true;
  } catch (err) {
    if (isAlreadyExists(err)) {
      logger.info("Invio già registrato, salto", { kind, userId, courseId });
      return false;
    }
    throw err;
  }
}

/** Marca la prenotazione come completata con successo. */
export async function confirmSend(
  db: Firestore,
  kind: DemoWebhookKind,
  userId: string,
  courseId: string
): Promise<void> {
  const ref = db.collection(DEMO_LOG_COLLECTION).doc(demoLogDocId(kind, userId, courseId));
  await ref.update({ ok: true });
}

/**
 * Rilascia la prenotazione se la POST è fallita, così un run successivo può
 * ritentare invece di trovare un claim orfano che blocca l'invio per sempre.
 */
export async function releaseSend(
  db: Firestore,
  kind: DemoWebhookKind,
  userId: string,
  courseId: string
): Promise<void> {
  const ref = db.collection(DEMO_LOG_COLLECTION).doc(demoLogDocId(kind, userId, courseId));
  try {
    await ref.delete();
  } catch (err) {
    // Non è fatale: al massimo il messaggio non verrà ritentato.
    logger.warn("Rilascio del claim fallito", {
      kind,
      userId,
      courseId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * `true` se la conferma di prenotazione per questa coppia è già partita oggi.
 *
 * Serve a non mandare due WhatsApp a poche ore di distanza a chi si iscrive il
 * giorno prima della lezione: `users/{uid}.courses` è un array di stringhe
 * senza data di iscrizione, quindi il log degli invii è l'unico posto dove
 * questa informazione esiste.
 */
export async function wasNotifiedToday(
  db: Firestore,
  userId: string,
  courseId: string,
  now: Date
): Promise<boolean> {
  const ref = db.collection(DEMO_LOG_COLLECTION).doc(demoLogDocId("booked", userId, courseId));
  const snap = await ref.get();
  if (!snap.exists) return false;
  const sentAt = toDate(snap.data()?.sentAt);
  return sentAt !== null && isSameRomeDay(sentAt, now);
}

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
  tipologiaIscrizione: string | null;
  isActive: boolean;
  courses: string[];
}

export interface DemoCourse {
  /** Valore con cui il corso compare in `users/{uid}.courses`. */
  uid: string;
  /** Id del documento, che su record anomali può differire da `uid`. */
  docId: string;
  name: string;
  startAt: Date | null;
  reminderEnabled: boolean;
}

export function mapDemoUserDoc(doc: DocLike): DemoUser {
  const data = doc.data() ?? {};
  return {
    uid: (data.uid as string) ?? doc.id,
    name: (data.name as string) ?? "",
    lastName: (data.lastName as string) ?? "",
    numeroTelefono: (data.numeroTelefono as string | undefined) ?? null,
    tipologiaIscrizione: (data.tipologiaIscrizione as string | undefined) ?? null,
    isActive: (data.isActive as boolean | undefined) ?? true,
    courses: Array.isArray(data.courses) ? (data.courses as unknown[]).map(String) : [],
  };
}

export function mapDemoCourseDoc(doc: DocLike): DemoCourse {
  const data = doc.data() ?? {};
  return {
    // Course.fromJson lato Flutter fa `uid ?? id`: replichiamo il fallback,
    // perché in passato sono esistiti documenti senza `uid`.
    uid: (data.uid as string) ?? (data.id as string) ?? doc.id,
    docId: doc.id,
    name: (data.name as string) ?? "",
    startAt: toDate(data.startDate),
    reminderEnabled: (data.reminderEnabled as boolean | undefined) ?? true,
  };
}

// ──────────────────────────────────────────────
//  Selezione del destinatario
// ──────────────────────────────────────────────

export type RecipientCheck =
  | { ok: true; nome: string; corso: string; phoneE164: string; startAt: Date }
  | { ok: false; reason: string };

/**
 * Verifica che la coppia utente/corso vada notificata. Pura: nessun accesso a
 * Firestore, così i casi limite sono tutti testabili in isolamento.
 *
 * `reminderEnabled` governa il promemoria ma non la conferma di prenotazione:
 * un admin che disattiva i promemoria di un corso non sta chiedendo di non
 * confermare più le iscrizioni.
 */
export function checkRecipient(
  kind: DemoWebhookKind,
  user: DemoUser,
  course: DemoCourse,
  now: Date
): RecipientCheck {
  if (user.tipologiaIscrizione !== TIPOLOGIA_PROVA) return { ok: false, reason: "not_trial" };
  if (!user.isActive) return { ok: false, reason: "inactive" };
  if (course.startAt === null) return { ok: false, reason: "course_without_date" };
  if (course.startAt.getTime() <= now.getTime()) return { ok: false, reason: "course_in_past" };
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
      reason: reason === "empty" || reason === "placeholder" ? "no_phone" : reason ?? "no_phone",
    };
  }
  if (!phone.likelyMobile) return { ok: false, reason: "not_mobile" };

  return { ok: true, nome, corso, phoneE164: phone.e164, startAt: course.startAt };
}

// ──────────────────────────────────────────────
//  Invio
// ──────────────────────────────────────────────

export interface MakeDeps {
  db: Firestore;
  webhookUrl: string;
  apiKey: string;
  post: (url: string, apiKey: string, payload: DemoLessonPayload) => Promise<PostResult>;
  now: Date;
}

export interface SendOutcome {
  sent: boolean;
  reason?: string;
  /** `true` se l'invio è stato tentato ma è andato storto (≠ scartato a monte). */
  failed?: boolean;
}

/**
 * Applica le guardie, prenota l'invio e chiama il webhook. Il claim viene
 * creato *prima* della POST e rilasciato se questa fallisce, così un run
 * successivo può ritentare senza rischiare un doppio messaggio nel frattempo.
 */
export async function dispatchDemoLesson(
  deps: MakeDeps,
  kind: DemoWebhookKind,
  user: DemoUser,
  course: DemoCourse
): Promise<SendOutcome> {
  const check = checkRecipient(kind, user, course, deps.now);
  if (!check.ok) return { sent: false, reason: check.reason };

  if (kind === "reminder" && (await wasNotifiedToday(deps.db, user.uid, course.uid, deps.now))) {
    return { sent: false, reason: "already_notified_today" };
  }

  const claimed = await claimSend(deps.db, kind, user.uid, course.uid, deps.now);
  if (!claimed) return { sent: false, reason: "already_sent" };

  const payload = buildDemoLessonPayload({
    kind,
    nome: check.nome,
    corso: check.corso,
    phoneE164: check.phoneE164,
    startAt: check.startAt,
  });

  let result: PostResult;
  try {
    result = await deps.post(deps.webhookUrl, deps.apiKey, payload);
  } catch (err) {
    await releaseSend(deps.db, kind, user.uid, course.uid);
    throw err;
  }

  if (!result.ok) {
    await releaseSend(deps.db, kind, user.uid, course.uid);
    return { sent: false, failed: true, reason: `post_failed_${result.status}` };
  }

  await confirmSend(deps.db, kind, user.uid, course.uid);
  return { sent: true };
}

// ──────────────────────────────────────────────
//  Callable: conferma immediata alla prenotazione
// ──────────────────────────────────────────────

const PRIVILEGED_ROLES = ["Admin", "Trainer"];

/** Legge un corso per `uid`, con fallback sull'id del documento. */
export async function findCourse(db: Firestore, courseId: string): Promise<DemoCourse | null> {
  const direct = await db.collection("courses").doc(courseId).get();
  if (direct.exists) {
    return mapDemoCourseDoc({ id: courseId, data: () => direct.data() });
  }
  // Alcuni documenti storici hanno un `uid` diverso dall'id del documento:
  // è per questo che anche il client interroga per campo (notification_service.dart).
  const query = await db
    .collection("courses")
    .where("uid", "==", courseId)
    .limit(1)
    .get();
  const doc = query.docs[0];
  return doc ? mapDemoCourseDoc({ id: doc.id, data: () => doc.data() }) : null;
}

/**
 * Notifica la prenotazione di una lezione di prova.
 *
 * Il client passa solo `{userId, courseId}`: utente e corso vengono risolti
 * server-side, così un client vecchio o manomesso non può decidere da sé chi è
 * un utente di prova né quale messaggio far partire.
 */
export async function notifyDemoLessonBookedHandler(
  request: HandlerRequest,
  deps: MakeDeps
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as { userId?: string; courseId?: string } | null;
  if (!payload || typeof payload !== "object" || !payload.userId || !payload.courseId) {
    throw new HttpsError("invalid-argument", "userId e courseId obbligatori");
  }
  const { userId, courseId } = payload;

  if (request.auth.uid !== userId) {
    const callerSnap = await deps.db.collection("users").doc(request.auth.uid).get();
    const role = (callerSnap.data()?.role as string | undefined) ?? "User";
    if (!PRIVILEGED_ROLES.includes(role)) {
      throw new HttpsError(
        "permission-denied",
        "Solo Admin e Trainer possono notificare altri utenti"
      );
    }
  }

  const userSnap = await deps.db.collection("users").doc(userId).get();
  if (!userSnap.exists) return { sent: false, reason: "user_not_found" };
  const user = mapDemoUserDoc({ id: userId, data: () => userSnap.data() });

  const course = await findCourse(deps.db, courseId);
  if (course === null) return { sent: false, reason: "course_not_found" };

  const outcome = await dispatchDemoLesson(deps, "booked", user, course);
  if (!outcome.sent) {
    logger.info("Conferma WhatsApp non inviata", { userId, courseId, reason: outcome.reason });
  }
  return { ...outcome };
}

// ──────────────────────────────────────────────
//  Cron: promemoria della sera prima
// ──────────────────────────────────────────────

export interface ReminderRunResult {
  /** Utenti PROVA letti: se cresce molto, conviene filtrare anche in query. */
  trialUsersRead: number;
  coursesTomorrow: number;
  candidates: number;
  sent: number;
  skipped: number;
  failed: number;
}

/**
 * Manda il promemoria WhatsApp per le lezioni di prova di domani.
 *
 * Le iscrizioni vivono solo su `users/{uid}.courses` (il documento corso ha
 * solo il contatore `subscribed`), quindi si parte dagli utenti di prova e si
 * incrociano con i corsi di domani. Entrambe le query usano un filtro su un
 * singolo campo: nessun indice composito da mantenere.
 */
export async function runDemoLessonReminders(deps: MakeDeps): Promise<ReminderRunResult> {
  const day = romeDayWindow(deps.now, 1);
  // Istante a metà del giorno target: riferimento robusto per isSameRomeDay.
  const reference = new Date((day.startMs + day.endMs) / 2);
  // Finestra allargata per non perdere l'ultima ora nel giorno del fall-back;
  // la precisione la dà il filtro isSameRomeDay qui sotto.
  const padded = romeDayWindowPadded(deps.now, 1);

  const [courseSnap, userSnap] = await Promise.all([
    deps.db
      .collection("courses")
      .where("startDate", ">=", Timestamp.fromMillis(padded.startMs))
      .where("startDate", "<=", Timestamp.fromMillis(padded.endMs))
      .get(),
    deps.db.collection("users").where("tipologiaIscrizione", "==", TIPOLOGIA_PROVA).get(),
  ]);

  const courses = courseSnap.docs
    .map((doc) => mapDemoCourseDoc({ id: doc.id, data: () => doc.data() }))
    .filter((c) => c.startAt !== null && isSameRomeDay(c.startAt, reference));

  const users = userSnap.docs.map((doc) =>
    mapDemoUserDoc({ id: doc.id, data: () => doc.data() })
  );

  const result: ReminderRunResult = {
    trialUsersRead: users.length,
    coursesTomorrow: courses.length,
    candidates: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
  };

  // Sequenziale e con try/catch per destinatario: il run deve completare sempre,
  // così lo scheduler non ritenta un batch di cui metà è già partito.
  for (const user of users) {
    const enrolled = courses.filter(
      (c) => user.courses.includes(c.uid) || user.courses.includes(c.docId)
    );
    for (const course of enrolled) {
      result.candidates++;
      try {
        const outcome = await dispatchDemoLesson(deps, "reminder", user, course);
        if (outcome.sent) {
          result.sent++;
        } else if (outcome.failed) {
          result.failed++;
          logger.error("Promemoria WhatsApp non consegnato", {
            userId: user.uid,
            courseId: course.uid,
            reason: outcome.reason,
          });
        } else {
          result.skipped++;
          logger.info("Promemoria WhatsApp saltato", {
            userId: user.uid,
            courseId: course.uid,
            reason: outcome.reason,
          });
        }
      } catch (err) {
        result.failed++;
        logger.error("Promemoria WhatsApp fallito", {
          userId: user.uid,
          courseId: course.uid,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  logger.info("Run promemoria WhatsApp completata", { ...result });
  return result;
}

// ──────────────────────────────────────────────
//  Callable di test (DebugEmailPage)
// ──────────────────────────────────────────────

/**
 * Manda un payload sintetico al numero indicato dal chiamante. Non tocca
 * Firestore e non scrive nel log degli invii: serve a far apprendere lo schema
 * a Make e a provare i template WhatsApp sul proprio numero.
 */
export async function sendTestDemoLessonWebhookHandler(
  request: HandlerRequest,
  deps: MakeDeps
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as
    | {
        kind?: string;
        numeroTelefono?: string;
        nome?: string;
        corso?: string;
        giorno?: string;
        orario?: string;
      }
    | null;
  if (!payload || typeof payload !== "object" || !payload.numeroTelefono) {
    throw new HttpsError("invalid-argument", "numeroTelefono obbligatorio");
  }

  const phone = normalizePhoneE164(payload.numeroTelefono);
  if (phone.e164 === null) {
    throw new HttpsError("invalid-argument", `Numero non valido (${phone.reason})`);
  }

  const kind: DemoWebhookKind = payload.kind === "reminder" ? "reminder" : "booked";
  // Domani a quest'ora: una data plausibile per il messaggio di prova.
  const startAt = new Date(deps.now.getTime() + 24 * 60 * 60 * 1000);

  // I campi non passati ricadono su valori plausibili, così il bottone di debug
  // funziona anche a form vuoto; quelli passati arrivano a Make verbatim, così
  // si può vedere il messaggio esatto che riceverà l'utente.
  const body = buildDemoLessonPayload({
    kind,
    nome: sanitizeTemplateParam(payload.nome) || "Test Test",
    corso: sanitizeTemplateParam(payload.corso) || "Lezione di prova",
    phoneE164: phone.e164,
    startAt,
    giorno: payload.giorno,
    orario: payload.orario,
  });

  const result = await deps.post(deps.webhookUrl, deps.apiKey, body);
  return { ok: result.ok, status: result.status, payload: { ...body } };
}
