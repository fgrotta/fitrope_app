// Modifica e revoca Admin di un abbonamento esistente (collezione
// `subscriptions`), con ricalcolo dello snapshot `activeSubscriptions`.
// La revoca conserva lo storico: il documento resta, con `revokedAt`.
// Nessuna delle due operazioni tocca le prenotazioni già fatte.

import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  buildSubscriptionFromPlan,
  computeActiveSnapshot,
  findOverlapping,
  recordFromDoc,
  recordToSnapshotEntry,
  UserSubscriptionRecord,
  validateWindow,
} from "./subscription";
import { requireAdmin, requirePlan } from "./provisioning";
import { TRIAL_PLAN_KEY } from "./trial";

type Firestore = admin.firestore.Firestore;
type FsData = admin.firestore.DocumentData;

export interface ManageSubscriptionRequest {
  auth?: { uid: string } | null;
  data: unknown;
}

function requireBody(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Body mancante o invalido");
  }
  return data as Record<string, unknown>;
}

function requireSubscriptionId(body: Record<string, unknown>): string {
  const id = body.subscriptionId;
  if (typeof id !== "string" || !id) {
    throw new HttpsError("invalid-argument", "subscriptionId richiesto");
  }
  return id;
}

/** Legge doc abbonamento (non revocabile se mancante), doc utente e tutti i suoi abbonamenti. */
async function readSubscriptionContext(
  tx: admin.firestore.Transaction,
  db: Firestore,
  subscriptionId: string,
) {
  const subRef = db.collection("subscriptions").doc(subscriptionId);
  const subSnap = await tx.get(subRef);
  if (!subSnap.exists) {
    throw new HttpsError("not-found", "Abbonamento inesistente");
  }
  const subData = subSnap.data() as FsData;
  const userId = subData.userId;
  if (typeof userId !== "string" || !userId) {
    throw new HttpsError("failed-precondition", "Abbonamento senza utente");
  }
  const userRef = db.collection("users").doc(userId);
  const [userSnap, allSnap] = await Promise.all([
    tx.get(userRef),
    tx.get(db.collection("subscriptions").where("userId", "==", userId)),
  ]);
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Utente inesistente");
  }
  const records = allSnap.docs.map((d) => recordFromDoc(d.id, d.data()));
  return { subRef, subData, userId, userRef, records };
}

/**
 * Modifica un abbonamento (Admin): piano (famiglia, modalità, variante,
 * durata), date e ingressi residui. Vale anche per gli scaduti. Una Prova
 * modificata diventa un abbonamento normale (la Prova non è un piano di
 * destinazione).
 *
 * [expectedRemainingEntries] è il residuo che l'Admin aveva sotto gli occhi:
 * se nel frattempo un'iscrizione o una disdetta l'ha cambiato, la modifica è
 * rifiutata (`aborted`) invece di sovrascriverlo con un valore stantio.
 *
 * Payload: { subscriptionId, planKey, startDateMillis, endDateMillis,
 *   remainingEntries?, expectedRemainingEntries? }
 */
export async function updateSubscriptionHandler(
  request: ManageSubscriptionRequest,
  db: Firestore,
  nowMillis: number = Date.now(),
): Promise<Record<string, unknown>> {
  await requireAdmin(request.auth, db);
  const actor = request.auth!.uid;
  const body = requireBody(request.data);
  const subscriptionId = requireSubscriptionId(body);
  const plan = requirePlan(body.planKey);
  if (plan.key === TRIAL_PLAN_KEY) {
    throw new HttpsError("invalid-argument", "La Prova non è selezionabile come tipologia");
  }
  validateWindow(body.startDateMillis, body.endDateMillis);
  const startMillis = body.startDateMillis as number;
  const endMillis = body.endDateMillis as number;

  let remainingEntries: number | null = null;
  if (plan.billingMode === "ENTRIES") {
    const value = body.remainingEntries;
    // Nessun tetto: l'Admin può dare più ingressi di quelli del pacchetto.
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
      throw new HttpsError(
        "invalid-argument",
        "Ingressi residui non validi: numero intero da 0 in su",
      );
    }
    remainingEntries = value;
  }

  let userId = "";
  await db.runTransaction(async (tx) => {
    const ctx = await readSubscriptionContext(tx, db, subscriptionId);
    userId = ctx.userId;
    if (ctx.subData.revokedAt) {
      throw new HttpsError("failed-precondition", "Abbonamento revocato: non modificabile");
    }
    const before = ctx.records.find((r) => r.id === subscriptionId)!;
    if (body.expectedRemainingEntries !== undefined &&
        (body.expectedRemainingEntries ?? null) !== before.remainingEntries) {
      throw new HttpsError(
        "aborted",
        "Gli ingressi sono cambiati nel frattempo: ricarica e riprova",
      );
    }

    if (findOverlapping(ctx.records, plan.family, startMillis, endMillis, subscriptionId)
      .length > 0) {
      throw new HttpsError(
        "already-exists",
        `Esiste già un abbonamento ${plan.family} in quelle date per questo utente`,
      );
    }

    const updated: UserSubscriptionRecord = {
      ...buildSubscriptionFromPlan(plan, startMillis, endMillis),
      id: subscriptionId,
      remainingEntries,
    };
    const history: FsData[] = Array.isArray(ctx.subData.editHistory)
      ? (ctx.subData.editHistory as FsData[])
      : [];
    const at = Timestamp.fromMillis(nowMillis);
    tx.update(ctx.subRef, {
      planKey: updated.planKey,
      family: updated.family,
      billingMode: updated.billingMode,
      courseTypeTags: updated.courseTypeTags,
      weeklyFrequency: updated.weeklyFrequency,
      remainingEntries: updated.remainingEntries,
      // Tetto dei rimborsi: senza, una disdetta riporterebbe un pacchetto
      // portato oltre il piano agli ingressi del piano.
      maxEntries: remainingEntries === null
        ? null
        : Math.max(plan.entries ?? 0, remainingEntries),
      startDate: Timestamp.fromMillis(updated.startDateMillis),
      endDate: Timestamp.fromMillis(updated.endDateMillis),
      updatedAt: at,
      updatedBy: actor,
      // Audit: un cambio piano conta per la contabilità.
      editHistory: [...history, {
        at,
        by: actor,
        before: {
          planKey: before.planKey,
          startDate: Timestamp.fromMillis(before.startDateMillis),
          endDate: Timestamp.fromMillis(before.endDateMillis),
          remainingEntries: before.remainingEntries,
        },
      }],
    });

    const records = ctx.records.map((r) => (r.id === subscriptionId ? updated : r));
    tx.update(ctx.userRef, {
      activeSubscriptions: computeActiveSnapshot(records, nowMillis).map(recordToSnapshotEntry),
    });
  });

  logger.info("Abbonamento modificato", {
    by: actor, userId, subscriptionId, planKey: plan.key,
  });
  return { ok: true, subscriptionId };
}

/**
 * Revoca un abbonamento (Admin) conservandone lo storico. Idempotente: su un
 * abbonamento già revocato non scrive nulla.
 *
 * Payload: { subscriptionId }
 */
export async function revokeSubscriptionHandler(
  request: ManageSubscriptionRequest,
  db: Firestore,
  nowMillis: number = Date.now(),
): Promise<Record<string, unknown>> {
  await requireAdmin(request.auth, db);
  const actor = request.auth!.uid;
  const subscriptionId = requireSubscriptionId(requireBody(request.data));

  let alreadyRevoked = false;
  let userId = "";
  await db.runTransaction(async (tx) => {
    const ctx = await readSubscriptionContext(tx, db, subscriptionId);
    userId = ctx.userId;
    // Assegnato (non accumulato): Firestore può rieseguire la closure.
    alreadyRevoked = !!ctx.subData.revokedAt;
    if (alreadyRevoked) return;

    tx.update(ctx.subRef, {
      revokedAt: Timestamp.fromMillis(nowMillis),
      revokedBy: actor,
      revokedReason: "ADMIN",
    });
    const records = ctx.records.map((r) =>
      r.id === subscriptionId ? { ...r, revokedAtMillis: nowMillis } : r);
    tx.update(ctx.userRef, {
      activeSubscriptions: computeActiveSnapshot(records, nowMillis).map(recordToSnapshotEntry),
    });
  });

  if (!alreadyRevoked) {
    logger.info("Abbonamento revocato", { by: actor, userId, subscriptionId });
  }
  return { ok: true, subscriptionId, alreadyRevoked };
}
