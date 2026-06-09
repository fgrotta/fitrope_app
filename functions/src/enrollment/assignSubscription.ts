import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { planByKey } from "./plansCatalog";
import {
  buildSubscriptionFromPlan,
  computeActiveSnapshot,
  hasActiveForFamily,
  UserSubscriptionRecord,
} from "./subscription";

export interface AssignRequest {
  auth?: { uid: string } | null;
  data: unknown;
}

type FsData = admin.firestore.DocumentData;

/** Record (millis) da un documento Firestore della collezione `subscriptions`. */
function recordFromDoc(id: string, data: FsData): UserSubscriptionRecord {
  const end = data.endDate;
  const start = data.startDate;
  return {
    id,
    planKey: data.planKey,
    family: data.family,
    billingMode: data.billingMode,
    courseTypeTags: data.courseTypeTags ?? [],
    weeklyFrequency: data.weeklyFrequency ?? null,
    remainingEntries: data.remainingEntries ?? null,
    startDateMillis: start && typeof start.toMillis === "function" ? start.toMillis() : 0,
    endDateMillis: end && typeof end.toMillis === "function" ? end.toMillis() : 0,
  };
}

/** Documento Firestore (collezione `subscriptions`) da un record. */
function recordToDoc(
  r: UserSubscriptionRecord,
  userId: string,
  createdBy: string
): FsData {
  const Timestamp = admin.firestore.Timestamp;
  return {
    userId,
    createdBy,
    planKey: r.planKey,
    family: r.family,
    billingMode: r.billingMode,
    courseTypeTags: r.courseTypeTags,
    weeklyFrequency: r.weeklyFrequency,
    remainingEntries: r.remainingEntries,
    startDate: Timestamp.fromMillis(r.startDateMillis),
    endDate: Timestamp.fromMillis(r.endDateMillis),
    createdAt: Timestamp.now(),
  };
}

/** Voce dello snapshot `activeSubscriptions` sul doc utente (mappa su Dart UserSubscription). */
function recordToSnapshotEntry(r: UserSubscriptionRecord): FsData {
  const Timestamp = admin.firestore.Timestamp;
  return {
    id: r.id ?? null,
    planKey: r.planKey,
    family: r.family,
    billingMode: r.billingMode,
    courseTypeTags: r.courseTypeTags,
    weeklyFrequency: r.weeklyFrequency,
    remainingEntries: r.remainingEntries,
    startDate: Timestamp.fromMillis(r.startDateMillis),
    endDate: Timestamp.fromMillis(r.endDateMillis),
  };
}

/**
 * Assegna un abbonamento (admin). Crea il documento in `subscriptions` e
 * ricalcola lo snapshot `activeSubscriptions` sul doc utente, in transazione.
 * Vincolo: massimo un abbonamento attivo per famiglia.
 */
export async function assignSubscriptionHandler(
  request: AssignRequest,
  db: admin.firestore.Firestore
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }
  const data = request.data as Record<string, unknown> | null;
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Body mancante o invalido");
  }
  const userId = data.userId;
  const planKey = data.planKey;
  if (typeof userId !== "string" || typeof planKey !== "string") {
    throw new HttpsError("invalid-argument", "userId e planKey sono richiesti");
  }

  // Solo Admin può assegnare abbonamenti.
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  const callerRole = callerSnap.exists ? callerSnap.data()?.role : null;
  if (callerRole !== "Admin") {
    throw new HttpsError("permission-denied", "Solo un Admin può assegnare abbonamenti");
  }

  const plan = planByKey(planKey);
  if (!plan) {
    throw new HttpsError("invalid-argument", `Piano sconosciuto: ${planKey}`);
  }

  const startMillis =
    typeof data.startDateMillis === "number" ? data.startDateMillis : Date.now();
  const record = buildSubscriptionFromPlan(plan, startMillis);

  const subColl = db.collection("subscriptions");
  const userRef = db.collection("users").doc(userId);
  const newRef = subColl.doc();

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(subColl.where("userId", "==", userId));
    const records = existing.docs.map((d) => recordFromDoc(d.id, d.data()));
    const active = computeActiveSnapshot(records, Date.now());

    if (hasActiveForFamily(active, plan.family)) {
      throw new HttpsError(
        "already-exists",
        `Esiste già un abbonamento ${plan.family} attivo per questo utente`
      );
    }

    tx.set(newRef, recordToDoc(record, userId, request.auth!.uid));

    const newActive: UserSubscriptionRecord = { ...record, id: newRef.id };
    const snapshot = [...active, newActive].map(recordToSnapshotEntry);
    tx.set(userRef, { activeSubscriptions: snapshot }, { merge: true });
  });

  logger.info("Abbonamento assegnato", {
    by: request.auth.uid,
    userId,
    planKey,
    subscriptionId: newRef.id,
  });

  return { ok: true, subscriptionId: newRef.id };
}
