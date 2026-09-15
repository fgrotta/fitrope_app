import { createHash } from "crypto";
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { planByKey } from "../enrollment/plansCatalog";
import {
  computeActiveSnapshot,
  recordFromDoc,
  recordToDoc,
  recordToSnapshotEntry,
  UserSubscriptionRecord,
} from "../enrollment/subscription";
import { legacySubscriptionMigrationMarker } from "./marker";
import {
  addMonthsInRome,
  timestampMillis,
  transformUser,
} from "./userTransform";

type PublicStatus =
  | "MIGRATED"
  | "AUTO_CONVERTIBLE"
  | "MANUAL_REQUIRED"
  | "CONFLICT"
  | "NOT_APPLICABLE";

function source(data: Record<string, unknown>): Record<string, unknown> {
  return {
    role: data.role,
    tipologiaCorsoTags: data.tipologiaCorsoTags,
    tipologiaIscrizione: data.tipologiaIscrizione,
    entrateDisponibili: data.entrateDisponibili,
    entrateSettimanali: data.entrateSettimanali,
    fineIscrizione: timestampMillis(data.fineIscrizione),
  };
}

function fingerprint(data: Record<string, unknown>): string {
  return createHash("sha256")
    .update(JSON.stringify(source(data)))
    .digest("hex");
}

async function requireAdmin(
  auth: { uid: string } | null | undefined,
  db: admin.firestore.Firestore,
): Promise<void> {
  if (!auth) throw new HttpsError("unauthenticated", "Login richiesto");
  const caller = await db.collection("users").doc(auth.uid).get();
  if (!caller.exists || caller.data()?.role !== "Admin") {
    throw new HttpsError(
      "permission-denied",
      "Solo un Admin può migrare abbonamenti legacy",
    );
  }
}

function validateUserId(data: unknown): string {
  const id = (data as Record<string, unknown> | null)?.userId;
  if (typeof id !== "string" || !id)
    throw new HttpsError("invalid-argument", "userId richiesto");
  return id;
}

function statusFor(
  data: Record<string, unknown>,
  id: string,
  now: number,
  existingSubscriptions: Array<Record<string, unknown>>,
): {
  status: PublicStatus;
  reasonCode: string;
  reasonDetail: string;
  target?: Record<string, unknown>;
  expectedFingerprint: string;
  legacy: Record<string, unknown>;
} {
  const legacy = source(data);
  if (data.legacySubscriptionMigration) {
    return {
      status: "MIGRATED",
      reasonCode: "ALREADY_MIGRATED",
      reasonDetail: "migrazione già registrata",
      expectedFingerprint: fingerprint(data),
      legacy,
    };
  }
  const decision = transformUser(id, data, now);
  if (decision.target) {
    if (
      existingSubscriptions.some(
        (subscription) => subscription.family === decision.target!.family,
      )
    ) {
      return {
        status: "CONFLICT",
        reasonCode: "EXISTING_SUBSCRIPTION_CONFLICT",
        reasonDetail: `esiste già una subscription ${decision.target.family}`,
        expectedFingerprint: fingerprint(data),
        legacy,
      };
    }
    return {
      status: "AUTO_CONVERTIBLE",
      reasonCode: decision.reasonCode,
      reasonDetail: decision.reasonDetail,
      target: { ...decision.target },
      expectedFingerprint: fingerprint(data),
      legacy,
    };
  }
  const tags = data.tipologiaCorsoTags;
  const manual =
    data.role === "User" &&
    typeof data.tipologiaIscrizione === "string" &&
    !(Array.isArray(tags) && tags.includes("Hey Mamma"));
  return {
    status: manual ? "MANUAL_REQUIRED" : "NOT_APPLICABLE",
    reasonCode: decision.reasonCode,
    reasonDetail: decision.reasonDetail,
    expectedFingerprint: fingerprint(data),
    legacy,
  };
}

export async function previewLegacyUserMigrationHandler(
  request: { auth?: { uid: string } | null; data: unknown },
  db: admin.firestore.Firestore,
): Promise<Record<string, unknown>> {
  await requireAdmin(request.auth, db);
  const userId = validateUserId(request.data);
  const snap = await db.collection("users").doc(userId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Utente inesistente");
  const subscriptions = await db
    .collection("subscriptions")
    .where("userId", "==", userId)
    .get();
  return statusFor(
    snap.data()!,
    userId,
    Date.now(),
    subscriptions.docs.map((doc) => doc.data()),
  );
}

function guidedRecord(
  userId: string,
  target: Record<string, unknown>,
): UserSubscriptionRecord {
  const planKey = target.planKey;
  const start = target.startDateMillis;
  const end = target.endDateMillis;
  if (
    typeof planKey !== "string" ||
    typeof start !== "number" ||
    typeof end !== "number"
  ) {
    throw new HttpsError(
      "invalid-argument",
      "target richiede planKey, startDateMillis e endDateMillis",
    );
  }
  const plan = planByKey(planKey);
  if (!plan) throw new HttpsError("invalid-argument", "Piano sconosciuto");
  if (addMonthsInRome(start, plan.durationMonths) !== end) {
    throw new HttpsError(
      "invalid-argument",
      "La durata del piano non è valida in Europe/Rome",
    );
  }
  const remaining = target.remainingEntries;
  if (
    plan.billingMode === "ENTRIES" &&
    (typeof remaining !== "number" ||
      !Number.isInteger(remaining) ||
      remaining < 0 ||
      remaining > (plan.entries ?? 0))
  ) {
    throw new HttpsError(
      "invalid-argument",
      "remainingEntries deve essere compreso nel credito del piano",
    );
  }
  if (
    plan.billingMode === "FREQUENCY" &&
    remaining !== null &&
    remaining !== undefined
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Un piano a frequenza non accetta remainingEntries",
    );
  }
  return {
    id: `legacy_guided_${userId}`,
    planKey: plan.key,
    family: plan.family,
    billingMode: plan.billingMode,
    courseTypeTags: [...plan.grantedCourseTypeTags],
    weeklyFrequency: plan.weeklyFrequency,
    remainingEntries:
      plan.billingMode === "ENTRIES" ? (remaining as number) : null,
    startDateMillis: start,
    endDateMillis: end,
  };
}

export async function migrateLegacyUserHandler(
  request: { auth?: { uid: string } | null; data: unknown },
  db: admin.firestore.Firestore,
): Promise<Record<string, unknown>> {
  await requireAdmin(request.auth, db);
  const body = request.data as Record<string, unknown> | null;
  const userId = validateUserId(body);
  const mode = body?.mode;
  const expected = body?.expectedFingerprint;
  if ((mode !== "AUTO" && mode !== "GUIDED") || typeof expected !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "mode AUTO/GUIDED ed expectedFingerprint sono richiesti",
    );
  }
  return db.runTransaction(async (tx) => {
    const userRef = db.collection("users").doc(userId);
    const user = await tx.get(userRef);
    if (!user.exists) throw new HttpsError("not-found", "Utente inesistente");
    const userData = user.data()!;
    if (fingerprint(userData) !== expected)
      throw new HttpsError("aborted", "SOURCE_DRIFT");
    if (userData.legacySubscriptionMigration)
      return { status: "MIGRATED", alreadyApplied: true };
    const automatic = transformUser(userId, userData, Date.now());
    let record: UserSubscriptionRecord;
    if (mode === "AUTO") {
      if (!automatic.target)
        throw new HttpsError("failed-precondition", "MANUAL_REQUIRED");
      record = { ...automatic.target };
    } else {
      record = guidedRecord(userId, body?.target as Record<string, unknown>);
    }
    const subRef = db.collection("subscriptions").doc(record.id!);
    const [target, existing] = await Promise.all([
      tx.get(subRef),
      tx.get(db.collection("subscriptions").where("userId", "==", userId)),
    ]);
    if (
      target.exists ||
      existing.docs.some((doc) => doc.data().family === record.family)
    ) {
      throw new HttpsError("already-exists", "TARGET_CONFLICT");
    }
    const all = existing.docs.map((doc) => recordFromDoc(doc.id, doc.data()));
    all.push(record);
    tx.create(subRef, recordToDoc(record, userId, "legacy-migration"));
    tx.update(userRef, {
      activeSubscriptions: computeActiveSnapshot(all, Date.now()).map(
        recordToSnapshotEntry,
      ),
      legacySubscriptionMigration: {
        ...legacySubscriptionMigrationMarker(
          mode === "AUTO" ? "ADMIN_AUTO" : "ADMIN_GUIDED",
          record.id!,
          record.planKey,
          request.auth!.uid,
        ),
      },
    });
    return { status: "MIGRATED", subscriptionId: record.id };
  });
}
