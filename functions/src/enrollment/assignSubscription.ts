import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { planByKey } from "./plansCatalog";
import {
  buildSubscriptionFromPlan,
  computeActiveSnapshot,
  defaultEndMillis,
  findOverlapping,
  recordFromDoc,
  recordToDoc,
  recordToSnapshotEntry,
  validateWindow,
} from "./subscription";
import { hasLegacyEconomicState, hasLegacyEntryConsumption } from "./provisioning";
import { TRIAL_PLAN_KEY } from "./trial";
import { legacySubscriptionMigrationMarker } from "../migration/marker";

export interface AssignRequest {
  auth?: { uid: string } | null;
  data: unknown;
}

type FsData = admin.firestore.DocumentData;

/**
 * Il legacy sul doc è solo un residuo, azzerabile dall'assegnazione: una Prova
 * V1 (sostituita dal nuovo abbonamento) oppure un utente già migrato, i cui
 * campi legacy restano sul documento dopo la conversione.
 */
function isLegacyResidue(user: FsData): boolean {
  return user.tipologiaIscrizione === "ABBONAMENTO_PROVA" ||
    !!user.legacySubscriptionMigration;
}

/**
 * Scadenza di una Prova V1 non migrata e ancora valida, altrimenti null. Una
 * Prova V1 scaduta (o senza scadenza) è solo un residuo.
 */
function liveLegacyTrialEnd(user: FsData, nowMillis: number): number | null {
  if (user.tipologiaIscrizione !== "ABBONAMENTO_PROVA" ||
      user.legacySubscriptionMigration) {
    return null;
  }
  const end = user.fineIscrizione;
  const endMillis = end && typeof end.toMillis === "function"
    ? (end.toMillis() as number)
    : null;
  return endMillis !== null && endMillis >= nowMillis ? endMillis : null;
}

/**
 * Registro consumi senza voci LEGACY_ENTRY: con i campi legacy azzerati, una
 * disiscrizione non deve rimettere `entrateDisponibili` e riportare l'utente
 * nel modello legacy.
 */
function withoutLegacyEntries(user: FsData): FsData {
  const raw = user.enrollmentConsumption;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  return Object.fromEntries(Object.entries(raw as FsData).map(([courseId, rec]) => [
    courseId,
    rec && typeof rec === "object" && (rec as FsData).kind === "LEGACY_ENTRY"
      ? { ...(rec as FsData), kind: "NONE" }
      : rec,
  ]));
}

/**
 * Assegna un abbonamento (admin). Crea il documento in `subscriptions` e
 * ricalcola lo snapshot `activeSubscriptions` sul doc utente, in transazione.
 * Vincolo: massimo un abbonamento per famiglia su finestre sovrapposte. Una
 * Prova sovrapposta viene chiusa (revocata) e sostituita. Una Prova V1 ancora
 * valida si sostituisce solo con un Open che inizia entro la sua scadenza:
 * qualunque altra assegnazione la cancellerebbe in silenzio, quindi è rifiutata.
 *
 * Payload: { userId, planKey, startDateMillis?, endDateMillis? }
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

  const startMillis = data.startDateMillis ?? Date.now();
  const endMillis = data.endDateMillis ??
    (typeof startMillis === "number" ? defaultEndMillis(plan, startMillis) : null);
  validateWindow(startMillis, endMillis);
  const record = buildSubscriptionFromPlan(
    plan, startMillis as number, endMillis as number,
  );

  const subColl = db.collection("subscriptions");
  const userRef = db.collection("users").doc(userId);
  const newRef = subColl.doc();
  const actor = request.auth.uid;
  let replacedTrialIds: string[] = [];
  let replacedLegacyTrial = false;

  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Utente inesistente");
    }
    const userData = userSnap.data()!;
    const hasLegacy =
      hasLegacyEconomicState(userData) || hasLegacyEntryConsumption(userData);
    if (hasLegacy && !isLegacyResidue(userData)) {
      throw new HttpsError(
        "failed-precondition",
        "L'utente è ancora sul modello legacy: eseguire prima la migrazione",
      );
    }

    const legacyTrialEnd = liveLegacyTrialEnd(userData, Date.now());
    const replacesLegacyTrial = legacyTrialEnd !== null &&
      plan.family === "OPEN" && record.startDateMillis <= legacyTrialEnd;
    if (legacyTrialEnd !== null && !replacesLegacyTrial) {
      throw new HttpsError(
        "failed-precondition",
        "La Prova è ancora attiva: può sostituirla solo un abbonamento Open " +
          "che inizia entro la sua scadenza",
      );
    }

    const existing = await tx.get(subColl.where("userId", "==", userId));
    const refById = new Map(existing.docs.map((d) => [d.id, d.ref]));
    const records = existing.docs.map((d) => recordFromDoc(d.id, d.data()));

    const conflicts = findOverlapping(
      records, plan.family, record.startDateMillis, record.endDateMillis,
    );
    if (conflicts.some((r) => r.planKey !== TRIAL_PLAN_KEY) ||
        (conflicts.length > 0 && plan.key === TRIAL_PLAN_KEY)) {
      throw new HttpsError(
        "already-exists",
        `Esiste già un abbonamento ${plan.family} in quelle date per questo utente`
      );
    }
    // Assegnato (non accumulato): Firestore può rieseguire la closure.
    replacedTrialIds = conflicts.map((r) => r.id!);
    replacedLegacyTrial = replacesLegacyTrial;

    // ----- scritture -----
    const nowMillis = Date.now();
    for (const trial of conflicts) {
      tx.update(refById.get(trial.id!)!, {
        revokedAt: Timestamp.fromMillis(nowMillis),
        revokedBy: actor,
        revokedReason: "REPLACED_BY_ASSIGNMENT",
        replacedBy: newRef.id,
      });
      trial.revokedAtMillis = nowMillis;
    }

    tx.set(newRef, recordToDoc(record, userId, actor));

    const snapshot = computeActiveSnapshot(
      [...records, { ...record, id: newRef.id }], nowMillis,
    ).map(recordToSnapshotEntry);
    const userUpdate: FsData = {
      activeSubscriptions: snapshot,
      subscriptionModelVersion: 2,
    };
    if (hasLegacy) {
      userUpdate.tipologiaIscrizione = null;
      userUpdate.entrateDisponibili = null;
      userUpdate.entrateSettimanali = null;
      userUpdate.fineIscrizione = null;
      userUpdate.enrollmentConsumption = withoutLegacyEntries(userData);
      if (!userData.legacySubscriptionMigration) {
        // Prova V1 non migrata: il marker chiude la card di migrazione e fa
        // rispondere migrateLegacyUser con alreadyApplied.
        userUpdate.legacySubscriptionMigration = legacySubscriptionMigrationMarker(
          "ADMIN_TRIAL_REPLACED", newRef.id, plan.key, actor,
        );
      }
    }
    tx.update(userRef, userUpdate);
  });

  logger.info("Abbonamento assegnato", {
    by: actor,
    userId,
    planKey,
    subscriptionId: newRef.id,
    replacedTrialIds,
    replacedLegacyTrial,
  });

  return { ok: true, subscriptionId: newRef.id, replacedTrialIds, replacedLegacyTrial };
}
