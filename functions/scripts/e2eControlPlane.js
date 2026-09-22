/* eslint-disable no-console */
// Control plane E2E: unica parte autorizzata a scrivere fixture direttamente.
// Non viene importato dall'app Flutter e rifiuta esplicitamente production.
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const command = process.argv[2];
const outputIndex = process.argv.indexOf("--manifest");
const manifestPath = outputIndex >= 0 ? process.argv[outputIndex + 1] : "integration_test/e2e_manifest.json";
const definesPath = manifestPath.replace(/\.json$/, ".defines.json");
const projectId = process.env.E2E_PROJECT_ID || process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "demo-fitrope";
const runId = process.env.E2E_RUN_ID || `${process.env.APP_ENV === "staging" ? "stg_e2e" : "e2e"}_${Date.now()}`;
const prefix = process.env.APP_ENV === "staging" ? "stg_e2e_" : "e2e_";
const password = "E2e-test-123!";

if (!command || !["setup", "assert", "cleanup"].includes(command)) {
  throw new Error("Usage: node e2eControlPlane.js <setup|assert|cleanup> [--manifest path]");
}
if (projectId === "fit-rope-app-1f575" || !projectId) {
  throw new Error("E2E refuses the production Firebase project");
}
if (process.env.APP_ENV === "staging" && !projectId.includes("staging")) {
  throw new Error("APP_ENV=staging requires a staging project id");
}

admin.initializeApp({ projectId });
const db = admin.firestore();
const now = () => admin.firestore.Timestamp.now();
const future = (days = 7) => admin.firestore.Timestamp.fromMillis(Date.now() + days * 86400000);
const leaseId = 'staging';

function user(uid, email, role) {
  return {
    uid, email, name: "E2E", lastName: role, role, courses: [],
    tipologiaIscrizione: null, entrateDisponibili: null, entrateSettimanali: null,
    fineIscrizione: null, isActive: true, isAnonymous: false, createdAt: now(),
    certificatoScadenza: future(180), numeroTelefono: null,
    tipologiaCorsoTags: role === "User" ? ["Open"] : ["Tutti i corsi"],
    cancelledEnrollments: [], waitlistCourses: [], emailNotificationsEnabled: true,
    pushNotificationsEnabled: false, regolamentoAccettatoIl: now(),
    activeSubscriptions: [], enrollmentConsumption: {},
  };
}

async function ensureAuth(uid, email, displayName) {
  try { await admin.auth().getUser(uid); }
  catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await admin.auth().createUser({ uid, email, password, displayName, emailVerified: true });
  }
}

function readManifest() {
  if (!fs.existsSync(manifestPath)) throw new Error(`Manifest absent: ${manifestPath}`);
  return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
}

async function setup() {
  if (process.env.APP_ENV === 'staging') {
    const leaseRef = db.collection('e2eLeases').doc(leaseId);
    const lease = await leaseRef.get();
    if (lease.exists && lease.data().expiresAt && lease.data().expiresAt.toMillis() > Date.now()) {
      throw new Error('E2E staging lease già occupato');
    }
    await leaseRef.set({ runId, owner: process.env.GITHUB_RUN_ID || 'local', expiresAt: future(2), createdAt: now() });
  }
  const ids = {
    admin: `${prefix}${runId}_admin`, trainer: `${prefix}${runId}_trainer`,
    member: `${prefix}${runId}_member`, waiter: `${prefix}${runId}_waiter`, legacy: `${prefix}${runId}_legacy`,
  };
  const users = Object.entries(ids).map(([kind, uid]) => ({
    kind, uid, email: `${uid}@example.test`, role: kind === "admin" ? "Admin" : kind === "trainer" ? "Trainer" : "User",
  }));
  for (const item of users) {
    await ensureAuth(item.uid, item.email, `E2E ${item.kind}`);
    await db.collection("users").doc(item.uid).set(item.kind === 'legacy'
      ? { ...user(item.uid, item.email, item.role), tipologiaIscrizione: 'PACCHETTO_ENTRATE', entrateDisponibili: 2, entrateSettimanali: 0, fineIscrizione: future(30) }
      : user(item.uid, item.email, item.role));
  }
  // Il piano è volutamente scritto come snapshot v2: le callable useranno la
  // stessa fonte di verità del runtime, senza aggirare le regole UI.
  for (const kind of ["member", "waiter"]) {
    const uid = ids[kind];
    const subscriptionId = `${prefix}${runId}_${kind}_open_2x_1m`;
    const record = {
      userId: uid, planKey: "open_2x_1m", family: "OPEN", billingMode: "FREQUENCY",
      courseTypeTags: ["Open"], weeklyFrequency: 2, remainingEntries: null,
      startDate: future(-1), endDate: future(30), createdAt: now(), assignedBy: ids.admin,
    };
    await db.collection("subscriptions").doc(subscriptionId).set(record);
    await db.collection("users").doc(uid).update({ activeSubscriptions: [{ ...record, id: subscriptionId }] });
  }
  const courseId = `${prefix}${runId}_course`;
  const courseDate = new Date(Date.now() + 7 * 86400000);
  await db.collection("courses").doc(courseId).set({
    id: courseId, uid: courseId, name: `[E2E] ${runId}`, startDate: admin.firestore.Timestamp.fromDate(courseDate), endDate: admin.firestore.Timestamp.fromMillis(courseDate.getTime() + 3600000),
    capacity: 1, subscribed: 0, trainerId: ids.trainer, courseType: "open", tags: ["Open"],
    tag: null, courseModelV2: true, sala: "Sala 1", waitlist: [], reminderEnabled: false, waitlistEnabled: true,
  });
  const legacyCourseId = `${prefix}${runId}_legacy_course`;
  await db.collection('courses').doc(legacyCourseId).set({
    id: legacyCourseId, uid: legacyCourseId, name: `[E2E Legacy] ${runId}`, startDate: admin.firestore.Timestamp.fromDate(courseDate),
    endDate: admin.firestore.Timestamp.fromMillis(courseDate.getTime() + 3600000), capacity: 10, subscribed: 0,
    trainerId: ids.trainer, courseType: 'open', tags: ['Open'], sala: 'Sala 1', waitlist: [], reminderEnabled: false, waitlistEnabled: true,
  });
  const manifest = {
    version: 1, projectId, runId, prefix, password, users, ids, courseId,
    E2E_ADMIN_EMAIL: users.find((u) => u.kind === "admin").email,
    E2E_TRAINER_EMAIL: users.find((u) => u.kind === "trainer").email,
    E2E_MEMBER_EMAIL: users.find((u) => u.kind === "member").email,
    E2E_WAITER_EMAIL: users.find((u) => u.kind === "waiter").email,
    E2E_LEGACY_EMAIL: users.find((u) => u.kind === "legacy").email,
    E2E_PASSWORD: password,
    E2E_COURSE_ID: courseId,
    E2E_LEGACY_COURSE_ID: legacyCourseId,
    E2E_COURSE_YEAR: String(courseDate.getFullYear()),
    E2E_COURSE_MONTH: String(courseDate.getMonth() + 1),
    E2E_COURSE_DAY: String(courseDate.getDate()),
    E2E_REGISTRATION_EMAIL: `${prefix}${runId}_registration@example.test`,
  };
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  fs.writeFileSync(definesPath, `${JSON.stringify({
    E2E_MEMBER_EMAIL: manifest.E2E_MEMBER_EMAIL,
    E2E_WAITER_EMAIL: manifest.E2E_WAITER_EMAIL,
    E2E_LEGACY_EMAIL: manifest.E2E_LEGACY_EMAIL,
    E2E_PASSWORD: manifest.E2E_PASSWORD,
    E2E_COURSE_YEAR: manifest.E2E_COURSE_YEAR,
    E2E_COURSE_MONTH: manifest.E2E_COURSE_MONTH,
    E2E_COURSE_DAY: manifest.E2E_COURSE_DAY,
    E2E_COURSE_ID: manifest.E2E_COURSE_ID,
    E2E_LEGACY_COURSE_ID: manifest.E2E_LEGACY_COURSE_ID,
    E2E_REGISTRATION_EMAIL: manifest.E2E_REGISTRATION_EMAIL,
  }, null, 2)}\n`);
  console.log(JSON.stringify(manifest));
}

async function assertState() {
  const manifest = readManifest();
  const course = (await db.collection("courses").doc(manifest.courseId).get()).data();
  if (!course) throw new Error("Fixture course missing");
  if (!Array.isArray(course.waitlist)) throw new Error("Course has no waitlist array");
  const member = (await db.collection("users").doc(manifest.ids.member).get()).data() || {};
  const waiter = (await db.collection("users").doc(manifest.ids.waiter).get()).data() || {};
  const waiterCourses = waiter.courses || [];
  if (course.subscribed !== 1 || course.waitlist.length !== 0 ||
      !waiterCourses.includes(manifest.courseId)) {
    throw new Error(`Enrollment finale inatteso: ${JSON.stringify({ subscribed: course.subscribed, waitlist: course.waitlist, waiterCourses })}`);
  }
  const legacy = (await db.collection('users').doc(manifest.ids.legacy).get()).data() || {};
  const legacyCourse = (await db.collection('courses').doc(manifest.E2E_LEGACY_COURSE_ID).get()).data();
  if ((legacy.entrateDisponibili ?? 0) !== 2 || (legacy.courses || []).length !== 0 ||
      legacyCourse?.subscribed !== 0) {
    throw new Error(`Rimborso legacy inatteso: ${JSON.stringify({ credits: legacy.entrateDisponibili, courses: legacy.courses, subscribed: legacyCourse?.subscribed })}`);
  }
  if (process.env.APP_ENV === 'staging' || process.env.FUNCTIONS_EMULATOR === 'true') {
    const receiptSnap = await db.collection('e2eNotificationReceipts')
      .where('courseId', '==', manifest.courseId).get();
    const receipt = receiptSnap.docs.map((doc) => doc.data())
      .find((data) => data.kind === 'waitlist' && data.requested === true);
    if (!receipt || !Array.isArray(receipt.recipients) ||
        !receipt.recipients.includes(manifest.ids.waiter)) {
      throw new Error('Ricevuta waitlist E2E mancante');
    }
  }
  console.log(JSON.stringify({ courseId: manifest.courseId, subscribed: course.subscribed, waitlist: course.waitlist, memberCourses: member.courses || [], waiterCourses }));
}

async function cleanup() {
  const manifest = readManifest();
  const userIds = manifest.users.map((u) => u.uid);
  const subscriptions = await db.collection("subscriptions").where("userId", "in", userIds).get();
  const receipts = await db.collection("e2eNotificationReceipts")
    .where("courseId", "==", manifest.courseId).get();
  const batch = db.batch();
  batch.delete(db.collection("courses").doc(manifest.courseId));
  batch.delete(db.collection('courses').doc(manifest.E2E_LEGACY_COURSE_ID));
  subscriptions.docs.forEach((doc) => batch.delete(doc.ref));
  receipts.docs.forEach((doc) => batch.delete(doc.ref));
  userIds.forEach((uid) => batch.delete(db.collection("users").doc(uid)));
  const runUsers = await db.collection('users').get();
  runUsers.docs.filter((doc) => String(doc.data().email || '').includes(manifest.runId))
    .forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  await Promise.all(userIds.map(async (uid) => {
    try { await admin.auth().deleteUser(uid); } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  }));
  const authUsers = await admin.auth().listUsers(1000);
  await Promise.all(authUsers.users
    .filter((record) => record.uid.includes(manifest.runId))
    .map((record) => admin.auth().deleteUser(record.uid)));
  if (fs.existsSync(manifestPath)) fs.unlinkSync(manifestPath);
  if (fs.existsSync(definesPath)) fs.unlinkSync(definesPath);
  if (process.env.APP_ENV === 'staging') {
    const leaseRef = db.collection('e2eLeases').doc(leaseId);
    const lease = await leaseRef.get();
    if (lease.data()?.runId === manifest.runId) await leaseRef.delete();
  }
}

({ setup, assert: assertState, cleanup })[command]().catch((error) => {
  console.error(error); process.exitCode = 1;
});
