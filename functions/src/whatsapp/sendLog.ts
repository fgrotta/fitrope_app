// Registro degli invii WhatsApp: `demoLessonWebhookLog/{kind}_{userId}_{courseId}`.
//
// Ogni messaggio è a pagamento, quindi l'invio si prenota con `create()` (atomico:
// protegge anche da due run concorrenti) PRIMA della POST, e il claim non si
// cancella mai. Make può aver accettato un messaggio anche se la risposta non è
// arrivata alla function: rendere ritentabile un esito incerto rischierebbe un
// secondo WhatsApp. Esiti:
//   pending  → claim creato, esito non ancora scritto (o interruzione dopo il claim);
//   sent     → Make ha risposto 2xx (`ok: true`);
//   rejected → Make ha rifiutato (4xx, compreso 429 dopo i tentativi);
//   unknown  → timeout, errore di rete, 5xx: da verificare in Make.
// Solo `ok: true` prova l'invio. Il documento contiene solo identificativi,
// istante ed esito: niente telefono, email, URL o chiave.

import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { isSameRomeDay } from "./format";
import { DemoWebhookKind } from "./payload";

export const DEMO_LOG_COLLECTION = "demoLessonWebhookLog";

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
  status?: number
): Promise<void> {
  await logRef(db, kind, userId, courseId).update({
    outcome,
    ok: outcome === "sent",
    // Status 0 = nessuna risposta HTTP: non c'è niente da registrare.
    ...(status !== undefined && status > 0 ? { status } : {}),
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
