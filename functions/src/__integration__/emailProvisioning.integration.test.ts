import * as admin from "firebase-admin";
import {
  checkEmailAvailabilityHandler,
  createManagedUserHandler,
  setManagedUserEmailHandler,
} from "../enrollment/provisioning";

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "demo-fitrope";
if (admin.apps.length === 0) admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const failTransactionsDb = new Proxy(db, {
  get(target, property) {
    if (property === "runTransaction") {
      return async () => { throw new Error("errore Firestore simulato"); };
    }
    const value = Reflect.get(target, property, target) as unknown;
    return typeof value === "function" ? value.bind(target) : value;
  },
}) as admin.firestore.Firestore;
let seq = 0;
const uniq = (prefix: string) => `${prefix}-${process.pid}-${++seq}`;

describe("provisioning email con Auth e Firestore emulator", () => {
  test("availability considera documenti, account Auth e email libera", async () => {
    const profileEmail = `${uniq("profile")}@test.it`;
    const authEmail = `${uniq("auth")}@test.it`;
    const authUid = uniq("auth-user");
    await db.collection("users").doc(uniq("legacy")).set({ email: profileEmail.toUpperCase() });
    await admin.auth().createUser({ uid: authUid, email: authEmail });
    expect(await checkEmailAvailabilityHandler({ data: { email: profileEmail.toUpperCase() } as never }, db)).toEqual({ available: false });
    expect(await checkEmailAvailabilityHandler({ data: { email: authEmail } as never }, db)).toEqual({ available: false });
    expect(await checkEmailAvailabilityHandler({ data: { email: `${uniq("free")}@test.it` } as never }, db)).toEqual({ available: true });
    await admin.auth().deleteUser(authUid);
  });

  test("creazione admin crea Auth con lo stesso UID e email normalizzata", async () => {
    const adminUid = uniq("admin");
    const email = `${uniq("managed")}@TEST.IT`;
    await db.collection("users").doc(adminUid).set({ uid: adminUid, email: `${adminUid}@test.it`, role: "Admin" });
    const result = await createManagedUserHandler({ auth: { uid: adminUid }, data: {
      name: "Ada", lastName: "Lovelace", role: "Admin", email,
    } }, db);
    const uid = result.userId;
    expect((await admin.auth().getUser(uid)).email).toBe(email.toLowerCase());
    expect((await db.collection("users").doc(uid).get()).data()?.email).toBe(email.toLowerCase());
    await admin.auth().deleteUser(uid);
    await db.collection("users").doc(uid).delete();
    await db.collection("users").doc(adminUid).delete();
  });

  test("creazione senza email lascia solo il profilo Firestore", async () => {
    const adminUid = uniq("admin");
    await db.collection("users").doc(adminUid).set({ role: "Admin" });
    const result = await createManagedUserHandler({ auth: { uid: adminUid }, data: {
      name: "Senza", lastName: "Email", role: "Admin",
    } }, db);
    expect((await db.collection("users").doc(result.userId).get()).exists).toBe(true);
    await expect(admin.auth().getUser(result.userId)).rejects.toMatchObject({ code: "auth/user-not-found" });
    await db.collection("users").doc(result.userId).delete();
    await db.collection("users").doc(adminUid).delete();
  });

  test("un errore Firestore compensa la creazione e il cambio dell'account Auth", async () => {
    const adminUid = uniq("admin");
    const newUid = uniq("rollback-new");
    const newEmail = `${uniq("rollback-create")}@test.it`;
    const oldUid = uniq("rollback-existing");
    const oldEmail = `${uniq("old-email")}@test.it`;
    const changedEmail = `${uniq("changed-email")}@test.it`;
    await db.collection("users").doc(adminUid).set({ role: "Admin" });
    await db.collection("users").doc(newUid).set({ uid: newUid, email: "-", role: "User" });
    await db.collection("users").doc(oldUid).set({ uid: oldUid, email: oldEmail, role: "User" });
    await admin.auth().createUser({ uid: oldUid, email: oldEmail });

    await expect(setManagedUserEmailHandler({ auth: { uid: adminUid }, data: {
      userId: newUid, email: newEmail,
    } }, failTransactionsDb)).rejects.toThrow("errore Firestore simulato");
    await expect(admin.auth().getUser(newUid)).rejects.toMatchObject({ code: "auth/user-not-found" });

    await expect(setManagedUserEmailHandler({ auth: { uid: adminUid }, data: {
      userId: oldUid, email: changedEmail,
    } }, failTransactionsDb)).rejects.toThrow("errore Firestore simulato");
    expect((await admin.auth().getUser(oldUid)).email).toBe(oldEmail);
    expect((await db.collection("users").doc(oldUid).get()).data()?.email).toBe(oldEmail);

    await Promise.all([newUid, oldUid, adminUid].map((uid) => db.collection("users").doc(uid).delete()));
    await admin.auth().deleteUser(oldUid);
  });

  test("un errore Firestore rimuove anche l'account appena creato da createManagedUser", async () => {
    const adminUid = uniq("admin");
    const email = `${uniq("rollback-managed")}@test.it`;
    await db.collection("users").doc(adminUid).set({ role: "Admin" });
    await expect(createManagedUserHandler({ auth: { uid: adminUid }, data: {
      name: "Errore", lastName: "Transazione", role: "Admin", email,
    } }, failTransactionsDb)).rejects.toThrow("errore Firestore simulato");
    await expect(admin.auth().getUserByEmail(email)).rejects.toMatchObject({ code: "auth/user-not-found" });
    await db.collection("users").doc(adminUid).delete();
  });

  test("email successiva crea account UID-matched e rifiuta collisioni", async () => {
    const adminUid = uniq("admin");
    const targetUid = uniq("target");
    const otherUid = uniq("other");
    const email = `${uniq("new-email")}@test.it`;
    await db.collection("users").doc(adminUid).set({ role: "Admin" });
    await db.collection("users").doc(targetUid).set({ uid: targetUid, email: "-", role: "User" });
    await db.collection("users").doc(otherUid).set({ uid: otherUid, email: `${uniq("taken")}@test.it`, role: "User" });
    const occupiedEmail = `${uniq("auth-taken")}@test.it`;
    const occupiedUid = uniq("auth-owner");
    await admin.auth().createUser({ uid: occupiedUid, email: occupiedEmail });
    const updated = await setManagedUserEmailHandler({ auth: { uid: adminUid }, data: { userId: targetUid, email: ` ${email.toUpperCase()} ` } }, db);
    expect(updated).toMatchObject({ ok: true, email: email.toLowerCase() });
    expect((await admin.auth().getUser(targetUid)).email).toBe(email.toLowerCase());
    await expect(setManagedUserEmailHandler({ auth: { uid: adminUid }, data: {
      userId: targetUid, email: (await db.collection("users").doc(otherUid).get()).data()?.email,
    } }, db)).rejects.toMatchObject({ code: "already-exists" });
    await expect(setManagedUserEmailHandler({ auth: { uid: adminUid }, data: {
      userId: targetUid, email: occupiedEmail,
    } }, db)).rejects.toMatchObject({ code: "already-exists" });
    await admin.auth().deleteUser(targetUid);
    await admin.auth().deleteUser(occupiedUid);
    await Promise.all([adminUid, targetUid, otherUid].map((uid) => db.collection("users").doc(uid).delete()));
  });
});
