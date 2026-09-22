import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { planByKey } from "./plansCatalog";
import {
  buildSubscriptionFromPlan,
  recordToDoc,
  recordToSnapshotEntry,
} from "./subscription";

type Data = Record<string, unknown>;
export interface ProvisionRequest { auth?: { uid: string } | null; data: unknown; }

export function hasLegacyEconomicState(user: Data): boolean {
  return user.tipologiaIscrizione != null || user.entrateDisponibili != null ||
    user.entrateSettimanali != null || user.fineIscrizione != null;
}

export function hasLegacyEntryConsumption(user: Data): boolean {
  const raw = user.enrollmentConsumption;
  return !!raw && typeof raw === "object" && !Array.isArray(raw) &&
    Object.values(raw as Data).some((value) =>
      value && typeof value === "object" && (value as Data).kind === "LEGACY_ENTRY");
}

async function requireAdmin(auth: { uid: string } | null | undefined, db: admin.firestore.Firestore) {
  if (!auth) throw new HttpsError("unauthenticated", "Login richiesto");
  const caller = await db.collection("users").doc(auth.uid).get();
  if (!caller.exists || caller.data()?.role !== "Admin") {
    throw new HttpsError("permission-denied", "Solo un Admin può gestire gli abbonamenti");
  }
}

function requirePlan(key: unknown) {
  if (typeof key !== "string") throw new HttpsError("invalid-argument", "planKey richiesto");
  const plan = planByKey(key);
  if (!plan) throw new HttpsError("invalid-argument", "Piano sconosciuto");
  return plan;
}

/** Crea utente gestito e primo piano nello stesso commit Firestore. */
export async function createManagedUserHandler(request: ProvisionRequest, db: admin.firestore.Firestore) {
  await requireAdmin(request.auth, db);
  const body = request.data as Data | null;
  if (!body || typeof body !== "object") throw new HttpsError("invalid-argument", "Body mancante");
  const name = body.name;
  const lastName = body.lastName;
  const role = body.role;
  if (typeof name !== "string" || !name.trim() || typeof lastName !== "string" || !lastName.trim()) {
    throw new HttpsError("invalid-argument", "Nome e cognome sono richiesti");
  }
  if (role !== "User" && role !== "Admin" && role !== "Trainer") {
    throw new HttpsError("invalid-argument", "Ruolo non valido");
  }
  const plan = role === "User" ? requirePlan(body.planKey) : null;
  if (role !== "User" && body.planKey != null) {
    throw new HttpsError("invalid-argument", "Solo un utente può avere un piano iniziale");
  }
  const userRef = db.collection("users").doc();
  const subRef = db.collection("subscriptions").doc();
  const record = plan ? buildSubscriptionFromPlan(plan, Date.now()) : null;
  await db.runTransaction(async (tx) => {
    const user: Data = {
      uid: userRef.id, email: typeof body.email === "string" && body.email.trim() ? body.email.trim() : "-",
      name: name.trim(), lastName: lastName.trim(), role, courses: [], isActive: true,
      isAnonymous: body.isAnonymous === true, createdAt: FieldValue.serverTimestamp(),
      numeroTelefono: typeof body.numeroTelefono === "string" && body.numeroTelefono.trim() ? body.numeroTelefono.trim() : null,
      cancelledEnrollments: [], waitlistCourses: [], emailNotificationsEnabled: true,
      pushNotificationsEnabled: true, activeSubscriptions: [], subscriptionModelVersion: 2,
    };
    if (record) {
      tx.create(subRef, recordToDoc(record, userRef.id, request.auth!.uid));
      user.activeSubscriptions = [recordToSnapshotEntry({ ...record, id: subRef.id })];
    }
    tx.create(userRef, user);
  });
  return { ok: true, userId: userRef.id, subscriptionId: record ? subRef.id : null };
}

/** Prova self-service: il marker e' scrivibile solo alla create self nelle rules. */
export async function grantSignupTrialHandler(request: ProvisionRequest, db: admin.firestore.Firestore) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login richiesto");
  const userRef = db.collection("users").doc(request.auth.uid);
  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) return { status: "NOT_PENDING" };
    const user = userSnap.data()! as Data;
    if (user.signupTrialRequested !== true) return { status: "NOT_PENDING" };
    if (user.uid !== request.auth!.uid || user.role !== "User" || user.isActive !== true ||
        hasLegacyEconomicState(user) || hasLegacyEntryConsumption(user)) {
      throw new HttpsError("failed-precondition", "Profilo signup non valido per la prova");
    }
    const existing = await tx.get(db.collection("subscriptions").where("userId", "==", request.auth!.uid));
    if (!existing.empty) {
      tx.update(userRef, { signupTrialRequested: FieldValue.delete() });
      return { status: "ALREADY_GRANTED" };
    }
    const plan = planByKey("open_trial_1i_30d")!;
    const record = buildSubscriptionFromPlan(plan, Date.now());
    const subRef = db.collection("subscriptions").doc();
    tx.create(subRef, recordToDoc(record, request.auth!.uid, "signup-trial"));
    tx.update(userRef, {
      activeSubscriptions: [recordToSnapshotEntry({ ...record, id: subRef.id })],
      subscriptionModelVersion: 2,
      signupTrialRequested: FieldValue.delete(),
      signupTrialGrantedAt: FieldValue.serverTimestamp(),
    });
    return { status: "GRANTED", subscriptionId: subRef.id };
  });
}

/** Audit-safe promotion for historical pure V2 documents. */
export function canReconcileSubscriptionModel(user: Data, subscriptions: Data[]): boolean {
  const version = typeof user.subscriptionModelVersion === "number"
    ? user.subscriptionModelVersion : 1;
  return version < 2 && subscriptions.length > 0 &&
    !hasLegacyEconomicState(user) && !hasLegacyEntryConsumption(user);
}
