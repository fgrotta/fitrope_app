// Riconciliazione Meta su transazioni Firestore reali: i callback possono
// precedere la risposta della POST o arrivare dopo la registrazione dell'invio.
import * as admin from "firebase-admin";
import { applyDeliveryStatus, claimSend, markSendOutcome, recordTestSend } from "../whatsapp/sendLog";

const projectId = process.env.GCLOUD_PROJECT ?? "demo-fitrope";
const app = admin.apps.find((candidate) => candidate?.name === "whatsapp-send-log") ??
  admin.initializeApp({ projectId }, "whatsapp-send-log");
const db = app.firestore();
const now = Date.now();
const id = (suffix: string) => `wa-${process.pid}-${now}-${suffix}`;

afterAll(async () => app.delete());

test("callback anticipato e successivo convergono sullo stesso registro", async () => {
  const userId = id("user");
  const courseId = id("course");
  const wamid = `wamid.${id("message")}`;
  const logId = `reminder_${userId}_${courseId}`;

  await claimSend(db, "reminder", userId, courseId, now);
  await expect(applyDeliveryStatus(db, wamid, "sent", now + 1000)).resolves.toBe("pending");
  await markSendOutcome(db, "reminder", userId, courseId, "sent", 200, {
    transport: "meta", messageId: wamid,
  });
  await expect(applyDeliveryStatus(db, wamid, "delivered", now + 2000)).resolves.toBe("applied");

  const log = (await db.collection("demoLessonWebhookLog").doc(logId).get()).data();
  expect(log).toMatchObject({ outcome: "sent", deliveryStatus: "delivered" });
  expect(JSON.stringify(log)).not.toContain(wamid);
});

test("una prova Meta assorbe lo stato arrivato prima della registrazione", async () => {
  const wamid = `wamid.${id("test-message")}`;
  const logId = `test_${id("admin")}`;
  await expect(applyDeliveryStatus(db, wamid, "read", now + 1000)).resolves.toBe("pending");
  await recordTestSend(db, logId, id("admin"), "reminder", 200, wamid, now);
  expect((await db.collection("demoLessonWebhookLog").doc(logId).get()).data())
    .toMatchObject({ deliveryStatus: "read", testKind: "reminder" });
});
