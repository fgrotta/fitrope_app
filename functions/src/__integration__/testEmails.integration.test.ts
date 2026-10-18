import * as admin from "firebase-admin";
import { sendTestEnrollmentEmailHandler } from "../enrollment/testEmails";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-fitrope";
if (admin.apps.length === 0) admin.initializeApp({ projectId });
const db = admin.firestore();
const prefix = `test-email-${process.pid}`;
const actor = `${prefix}-admin`;
const member = `${prefix}-member`;
const payload = {
  externalId: member, kind: "waitlist", courseName: "Pilates",
  courseDate: "20 ottobre", courseTime: "10:00", spotsAvailable: 1,
};

beforeAll(async () => {
  await db.collection("users").doc(actor).set({ role: "Admin" });
  await db.collection("users").doc(member).set({ role: "User", email: " QA@Example.com " });
  await admin.auth().createUser({ uid: actor, email: `${actor}@example.com`, password: "test1234" });
  await admin.auth().createUser({ uid: member, email: `${member}@example.com`, password: "test1234" });
});

afterAll(async () => {
  await Promise.all([actor, member].flatMap((uid) => [
    db.collection("users").doc(uid).delete(), admin.auth().deleteUser(uid),
  ]));
});

async function token(uid: string): Promise<string> {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
  const response = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: `${uid}@example.com`, password: "test1234", returnSecureToken: true }),
  });
  const data = await response.json() as { idToken: string };
  if (!data.idToken) throw new Error("Login emulatore fallito");
  return data.idToken;
}

async function call(idToken?: string, data: unknown = payload) {
  const host = process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1:5001";
  const response = await fetch(`http://${host}/${projectId}/europe-west8/sendTestEnrollmentEmail`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return response.json() as Promise<{ error?: { status: string } }>;
}

test("callable reale: richiede login e ruolo Admin prima del trasporto", async () => {
  expect((await call()).error?.status).toBe("UNAUTHENTICATED");
  expect((await call(await token(member))).error?.status).toBe("PERMISSION_DENIED");
  expect((await call(await token(actor), {})).error?.status).toBe("INVALID_ARGUMENT");
});

test("Firestore reale: destinatario dal profilo e template server, trasporto finto", async () => {
  const ensure = jest.fn(async () => ({}));
  const post = jest.fn(async (_data: Record<string, unknown>) => ({ id: "fake-notification" }));
  const result = await sendTestEnrollmentEmailHandler(
    { auth: { uid: actor }, data: { ...payload, email: "ignored@example.com" } },
    "dummy-key", { db, ensure, post },
  );
  expect(result).toEqual({ id: "fake-notification" });
  expect(ensure).toHaveBeenCalledWith(member, "qa@example.com", "dummy-key");
  expect(post.mock.calls[0][0].email_preheader).toContain("Pilates");
});
