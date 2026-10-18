// Registro degli invii WhatsApp: `demoLessonWebhookLog/{kind}_{userId}_{courseId}`.
//
// Ogni messaggio è a pagamento, quindi l'invio si prenota con `create()` (atomico:
// protegge anche da due run concorrenti) PRIMA della POST, e il claim non si
// cancella mai. Make (o Meta) può aver accettato un messaggio anche se la risposta non è
// arrivata alla function: rendere ritentabile un esito incerto rischierebbe un
// secondo WhatsApp. Esiti:
//   pending  → claim creato, esito non ancora scritto (o interruzione dopo il claim);
//   sent     → il trasporto ha risposto 2xx (`ok: true`);
//   rejected → rifiuto (4xx, compreso il rate limit dopo i tentativi);
//   unknown  → timeout, errore di rete, 5xx: da verificare in Make o nel
//              WhatsApp Manager (senza wamid il webhook di stato non riconcilia).
// Solo `ok: true` prova l'invio. Il documento contiene solo identificativi,
// istante ed esito: niente telefono, email, URL o chiave.
//
// Con Meta, il webhook di stato (statusWebhook.ts) aggiunge poi l'esito di
// CONSEGNA, ritrovando il documento dall'hash del wamid (`messageIdHash`: il
// wamid in chiaro contiene il numero, vedi transport.ts): `deliveryStatus`
// sent < delivered < read, oppure failed con `deliveryError`. È solo
// informativo: claim e soppressioni continuano a guardare `ok`.

import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";
import type { DocumentData, Firestore } from "firebase-admin/firestore";
import { isSameRomeDay } from "./format";
import { DemoWebhookKind } from "./payload";
import { WhatsappTransportName, hashMessageId } from "./transport";

export const DEMO_LOG_COLLECTION = "demoLessonWebhookLog";
/**
 * Raccordo per hash del wamid (`{hash}` → `logDocId` + ultimo stato di
 * consegna). Esiste perché Meta può chiamare il webhook prima che la function
 * abbia registrato l'esito della POST: lo stato resta qui e `markSendOutcome`
 * lo trasferisce sul registro nella stessa transazione. Solo server.
 */
export const DEMO_MESSAGE_COLLECTION = "demoLessonWhatsappMessages";

/** `claimed`: si può inviare. `sent`: già partito. `needs_review`: esito da verificare in Make. */
export type ClaimResult = "claimed" | "sent" | "needs_review";

export type SendLogOutcome = "sent" | "rejected" | "unknown";

/**
 * `(kind, userId, courseId)` è già una chiave univoca: un corso ha una sola
 * data, quindi il giorno non entra nell'id — se un admin spostasse la lezione,
 * un id datato farebbe partire un secondo invio.
 */
export function demoLogDocId(kind: DemoWebhookKind, userId: string, courseId: string): string {
  if (!userId || !courseId || userId.includes("/") || courseId.includes("/")) {
    throw new Error("userId/courseId non validi per un id di documento Firestore");
  }
  return `${kind}_${userId}_${courseId}`;
}

function logRef(db: Firestore, kind: DemoWebhookKind, userId: string, courseId: string) {
  return db.collection(DEMO_LOG_COLLECTION).doc(demoLogDocId(kind, userId, courseId));
}

function isAlreadyExists(err: unknown): boolean {
  const code = (err as { code?: number | string } | null)?.code;
  if (code === 6 || code === "6" || code === "already-exists") return true;
  const message = err instanceof Error ? err.message : String(err);
  return /already exists/i.test(message);
}

function toMillisOrNull(value: unknown): number | null {
  const maybe = value as { toMillis?: () => number } | null;
  if (maybe && typeof maybe.toMillis === "function") return maybe.toMillis();
  return null;
}

/** Prenota l'invio prima della POST. Rilancia gli errori Firestore diversi da ALREADY_EXISTS. */
export async function claimSend(
  db: Firestore,
  kind: DemoWebhookKind,
  userId: string,
  courseId: string,
  nowMillis: number
): Promise<ClaimResult> {
  const ref = logRef(db, kind, userId, courseId);
  try {
    await ref.create({
      kind,
      userId,
      courseId,
      outcome: "pending",
      ok: false,
      sentAt: Timestamp.fromMillis(nowMillis),
    });
    return "claimed";
  } catch (err) {
    if (!isAlreadyExists(err)) throw err;
  }

  const existing = (await ref.get()).data();
  // Anche i documenti legacy senza `ok` richiedono verifica: non provano l'invio.
  if (existing?.ok === true) return "sent";
  logger.warn("Invio WhatsApp con esito da verificare in Make: nessun nuovo tentativo", {
    kind,
    userId,
    courseId,
    outcome: (existing?.outcome as string | undefined) ?? "legacy",
  });
  return "needs_review";
}

export interface SendOutcomeDetails {
  transport?: WhatsappTransportName;
  /** wamid di Meta: se ne salva solo l'hash, la chiave del webhook di stato. */
  messageId?: string;
  /** `error.code` della Graph API. */
  errorCode?: number;
}

/**
 * Scrive l'esito sul claim. Rilancia gli errori: se fallisce dopo un 2xx il
 * claim resta `pending` e il chiamante lo segnala per verifica, senza ripetere la POST.
 */
export async function markSendOutcome(
  db: Firestore,
  kind: DemoWebhookKind,
  userId: string,
  courseId: string,
  outcome: SendLogOutcome,
  status?: number,
  details: SendOutcomeDetails = {}
): Promise<void> {
  const ref = logRef(db, kind, userId, courseId);
  const patch = {
    outcome,
    ok: outcome === "sent",
    // Status 0 = nessuna risposta HTTP: non c'è niente da registrare.
    ...(status !== undefined && status > 0 ? { status } : {}),
    ...(details.transport ? { transport: details.transport } : {}),
    ...(details.messageId ? { messageIdHash: hashMessageId(details.messageId) } : {}),
    ...(details.errorCode !== undefined ? { errorCode: details.errorCode } : {}),
  };
  if (!details.messageId) {
    await ref.update(patch);
    return;
  }
  const messageRef = db.collection(DEMO_MESSAGE_COLLECTION).doc(hashMessageId(details.messageId));
  await db.runTransaction(async (tx) => {
    const message = (await tx.get(messageRef)).data();
    tx.update(ref, { ...patch, ...deliveryFields(message) });
    tx.set(messageRef, { logDocId: ref.id }, { merge: true });
  });
}

/** Registra una prova Meta con la stessa riconciliazione atomica degli invii normali. */
export async function recordTestSend(
  db: Firestore,
  docId: string,
  uid: string,
  kind: DemoWebhookKind,
  status: number,
  messageId: string,
  nowMillis: number
): Promise<void> {
  const ref = db.collection(DEMO_LOG_COLLECTION).doc(docId);
  const messageRef = db.collection(DEMO_MESSAGE_COLLECTION).doc(hashMessageId(messageId));
  await db.runTransaction(async (tx) => {
    const message = (await tx.get(messageRef)).data();
    tx.create(ref, {
      kind: "test",
      testKind: kind,
      userId: uid,
      transport: "meta",
      messageIdHash: hashMessageId(messageId),
      outcome: "sent",
      ok: true,
      status,
      sentAt: Timestamp.fromMillis(nowMillis),
      ...deliveryFields(message),
    });
    tx.set(messageRef, { logDocId: docId }, { merge: true });
  });
}

/**
 * `true` se la conferma di prenotazione per questa coppia è partita con
 * successo nel giorno di Roma di `noticeDayMillis`.
 *
 * Serve a non mandare due WhatsApp a poche ore di distanza a chi si iscrive il
 * giorno prima della lezione: `users/{uid}.courses` non ha la data di
 * iscrizione, quindi il registro è l'unico posto dove questa informazione esiste.
 * Un claim pending/unknown/rejected non prova l'invio e non sopprime nulla.
 */
export async function wasNotifiedToday(
  db: Firestore,
  userId: string,
  courseId: string,
  noticeDayMillis: number
): Promise<boolean> {
  const data = (await logRef(db, "booked", userId, courseId).get()).data();
  if (data?.ok !== true) return false;
  const sentAt = toMillisOrNull(data.sentAt);
  return sentAt !== null && isSameRomeDay(sentAt, noticeDayMillis);
}

// ──────────────────────────────────────────────
//  Esiti di consegna (webhook di stato Meta)
// ──────────────────────────────────────────────

export type DeliveryStatus = "sent" | "delivered" | "read" | "failed";

const DELIVERY_RANK: Record<Exclude<DeliveryStatus, "failed">, number> = {
  sent: 1,
  delivered: 2,
  read: 3,
};

export function isDeliveryStatus(value: unknown): value is DeliveryStatus {
  return value === "sent" || value === "delivered" || value === "read" || value === "failed";
}

/**
 * I callback arrivano duplicati e fuori ordine: lo stato avanza solo di rango.
 * `failed` è terminale, ma non smentisce una consegna già confermata
 * (delivered/read provano che il messaggio è arrivato).
 */
export function shouldApplyDeliveryStatus(
  current: DeliveryStatus | undefined,
  next: DeliveryStatus
): boolean {
  if (current === "failed") return false;
  if (next === "failed") return current === undefined || current === "sent";
  return DELIVERY_RANK[next] > (current === undefined ? 0 : DELIVERY_RANK[current]);
}

/** Id del documento con questo wamid, se l'invio è già stato registrato. */
export async function findByMessageId(db: Firestore, messageId: string): Promise<string | null> {
  const snap = await db.collection(DEMO_MESSAGE_COLLECTION).doc(hashMessageId(messageId)).get();
  if (typeof snap.data()?.logDocId === "string") return snap.data()!.logDocId;
  // Documenti creati prima dell'indice: mantieni la riconciliazione dopo il deploy.
  const legacy = await db.collection(DEMO_LOG_COLLECTION)
    .where("messageIdHash", "==", hashMessageId(messageId)).limit(1).get();
  return legacy.docs[0]?.id ?? null;
}

export type DeliveryApplyResult = "applied" | "stale" | "pending";

function deliveryFields(data: DocumentData | undefined): Record<string, unknown> {
  if (!isDeliveryStatus(data?.deliveryStatus)) return {};
  return {
    deliveryStatus: data.deliveryStatus,
    deliveryUpdatedAt: data.deliveryUpdatedAt,
    ...(data.deliveryError !== undefined ? { deliveryError: data.deliveryError } : {}),
  };
}

/** Rilancia gli errori Firestore: il webhook li logga e risponde 200 comunque. */
export async function applyDeliveryStatus(
  db: Firestore,
  messageId: string,
  status: DeliveryStatus,
  timestampMillis: number,
  error?: { code?: number; title?: string }
): Promise<DeliveryApplyResult> {
  const messageRef = db.collection(DEMO_MESSAGE_COLLECTION).doc(hashMessageId(messageId));
  const legacyDocId = await findByMessageId(db, messageId);
  return db.runTransaction(async (tx) => {
    const message = (await tx.get(messageRef)).data();
    const logDocId = typeof message?.logDocId === "string" ? message.logDocId : legacyDocId;
    const logRef = logDocId ? db.collection(DEMO_LOG_COLLECTION).doc(logDocId) : null;
    const log = logRef ? (await tx.get(logRef)).data() : undefined;
    const current = message?.deliveryStatus ?? log?.deliveryStatus;
    if (!shouldApplyDeliveryStatus(isDeliveryStatus(current) ? current : undefined, status)) {
      return "stale";
    }
    const patch = {
      deliveryStatus: status,
      deliveryUpdatedAt: Timestamp.fromMillis(timestampMillis),
      ...(status === "failed" && error
        ? {
            deliveryError: {
              ...(typeof error.code === "number" ? { code: error.code } : {}),
              ...(typeof error.title === "string" ? { title: error.title } : {}),
            },
          }
        : {}),
    };
    tx.set(messageRef, { ...patch, ...(logDocId ? { logDocId } : {}) }, { merge: true });
    if (logRef) {
      tx.update(logRef, patch);
      return "applied";
    }
    return "pending";
  });
}
