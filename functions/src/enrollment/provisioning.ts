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

export function normalizeManagedEmail(value: unknown, required = false): string | null {
  if (typeof value !== "string" || !value.trim()) {
    if (required) throw new HttpsError("invalid-argument", "Email richiesta");
    return null;
  }
  const email = value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Inserisci un'email valida");
  }
  return email;
}

async function emailTakenByProfile(db: admin.firestore.Firestore, email: string, exceptUid?: string) {
  // I documenti pre-normalizzazione possono avere maiuscole arbitrarie: Firestore
  // non offre query case-insensitive, quindi il controllo confronta i valori normalizzati.
  const matches = await db.collection("users").get();
  return matches.docs.some((doc) => doc.id !== exceptUid &&
    typeof doc.data().email === "string" && doc.data().email.trim().toLowerCase() === email);
}

export async function checkEmailAvailabilityHandler(
  request: ProvisionRequest, db: admin.firestore.Firestore, authClient: admin.auth.Auth = admin.auth(),
) {
  const body = request.data as Data | null;
  if (!body || typeof body !== "object") throw new HttpsError("invalid-argument", "Body mancante");
  const email = normalizeManagedEmail(body.email, true)!;
  if (await emailTakenByProfile(db, email)) return { available: false };
  try {
    await authClient.getUserByEmail(email);
    return { available: false };
  } catch (error) {
    if ((error as { code?: string }).code === "auth/user-not-found") return { available: true };
    throw error;
  }
}

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
export async function createManagedUserHandler(
  request: ProvisionRequest, db: admin.firestore.Firestore, authClient: admin.auth.Auth = admin.auth(),
) {
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
  const email = normalizeManagedEmail(body.email);
  if (role !== "User" && body.planKey != null) {
    throw new HttpsError("invalid-argument", "Solo un utente può avere un piano iniziale");
  }
  const userRef = db.collection("users").doc();
  const subRef = db.collection("subscriptions").doc();
  const record = plan ? buildSubscriptionFromPlan(plan, Date.now()) : null;
  let authCreated = false;
  if (email) {
    if (await emailTakenByProfile(db, email)) throw new HttpsError("already-exists", "Questa email è già associata a un profilo. Contatta la palestra.");
    try {
      await authClient.getUserByEmail(email);
      throw new HttpsError("already-exists", "Questa email è già associata a un account.");
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
    }
    try {
      await authClient.createUser({ uid: userRef.id, email });
      authCreated = true;
    } catch (error) {
      if ((error as { code?: string }).code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "Questa email è già associata a un account.");
      }
      // Se la chiamata Auth è terminata con timeout dopo il commit remoto,
      // controlla l'UID scelto e rimuovi l'account orfano prima di rispondere.
      try {
        const possiblyCreated = await authClient.getUser(userRef.id);
        if (possiblyCreated.email?.toLowerCase() === email) {
          await authClient.deleteUser(userRef.id);
        }
      } catch (_) {
        // Mantieni l'errore di provisioning originale.
      }
      throw new HttpsError("internal", "Impossibile creare l'account di accesso");
    }
  }
  try {
    await db.runTransaction(async (tx) => {
    if (email) {
      const profiles = await tx.get(db.collection("users"));
      if (profiles.docs.some((doc) => typeof doc.data().email === "string" &&
          doc.data().email.trim().toLowerCase() === email)) {
        throw new HttpsError("already-exists", "Questa email è già associata a un profilo. Contatta la palestra.");
      }
    }
    const user: Data = {
      uid: userRef.id, email: email ?? "-",
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
  } catch (error) {
    if (authCreated) await authClient.deleteUser(userRef.id).catch(() => undefined);
    throw error;
  }
  return { ok: true, userId: userRef.id, subscriptionId: record ? subRef.id : null };
}

/** Aggiunge o modifica l'email e garantisce l'account Auth con lo stesso UID. */
export async function setManagedUserEmailHandler(
  request: ProvisionRequest, db: admin.firestore.Firestore, authClient: admin.auth.Auth = admin.auth(),
) {
  await requireAdmin(request.auth, db);
  const body = request.data as Data | null;
  if (!body || typeof body !== "object" || typeof body.userId !== "string" || !body.userId.trim()) {
    throw new HttpsError("invalid-argument", "userId richiesto");
  }
  const uid = body.userId.trim();
  const email = normalizeManagedEmail(body.email, true)!;
  const userRef = db.collection("users").doc(uid);
  const profile = await userRef.get();
  if (!profile.exists) throw new HttpsError("not-found", "Profilo non trovato");
  if (await emailTakenByProfile(db, email, uid)) throw new HttpsError("already-exists", "Questa email è già associata a un profilo. Contatta la palestra.");

  let existingAuth: admin.auth.UserRecord | null = null;
  try { existingAuth = await authClient.getUser(uid); }
  catch (error) { if ((error as { code?: string }).code !== "auth/user-not-found") throw error; }
  if (existingAuth && !existingAuth.email) {
    throw new HttpsError("failed-precondition", "L'account Auth esistente non ha un'email ripristinabile");
  }
  try {
    const byEmail = await authClient.getUserByEmail(email);
    if (byEmail.uid !== uid) throw new HttpsError("already-exists", "Questa email è già associata a un account.");
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
  }

  let createdAuth = false;
  try {
    if (existingAuth) await authClient.updateUser(uid, { email });
    else { await authClient.createUser({ uid, email }); createdAuth = true; }
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(userRef);
      if (!fresh.exists) throw new HttpsError("not-found", "Profilo non trovato");
      const duplicate = await tx.get(db.collection("users"));
      if (duplicate.docs.some((doc) => doc.id !== uid && typeof doc.data().email === "string" &&
          doc.data().email.trim().toLowerCase() === email)) {
        throw new HttpsError("already-exists", "Questa email è già associata a un profilo. Contatta la palestra.");
      }
      tx.update(userRef, { email });
    });
    return { ok: true, userId: uid, email };
  } catch (error) {
    if (createdAuth) await authClient.deleteUser(uid).catch(() => undefined);
    else if (existingAuth?.email) await authClient.updateUser(uid, { email: existingAuth.email }).catch(() => undefined);
    if ((error as { code?: string }).code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Questa email è già associata a un account.");
    }
    throw error;
  }
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
