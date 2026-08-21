/* eslint-disable no-console */

// Operazioni host-side per gli E2E. Richiede esattamente uno dei flag
// --emulator / --confirm-staging e rifiuta sempre il progetto produzione.

const args = process.argv.slice(2);
const command = args[0];
const emulator = args.includes("--emulator");
const staging = args.includes("--confirm-staging");

function valueAfter(flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
}

if (emulator === staging) {
  throw new Error("Specify exactly one of --emulator or --confirm-staging");
}

let projectId;
if (emulator) {
  projectId = "fit-rope-app-1f575";
  process.env.FIRESTORE_EMULATOR_HOST =
    process.env.FIRESTORE_EMULATOR_HOST || "localhost:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST =
    process.env.FIREBASE_AUTH_EMULATOR_HOST || "localhost:9099";
} else {
  projectId = process.env.STAGING_PROJECT_ID;
  if (
    !projectId ||
    !projectId.includes("staging") ||
    projectId === "fit-rope-app-1f575"
  ) {
    throw new Error("Refusing non-staging project");
  }
}

const admin = require("firebase-admin");
const { Firestore, Timestamp } = require("firebase-admin/firestore");

function stagingCredential() {
  const accessToken = process.env.GOOGLE_OAUTH_ACCESS_TOKEN;
  if (!accessToken) return undefined;
  return {
    getAccessToken: async () => ({
      access_token: accessToken,
      expires_in: 3600,
    }),
  };
}

const options = { projectId };
const credential = staging ? stagingCredential() : undefined;
if (credential) options.credential = credential;
admin.initializeApp(options);
const db = new Firestore({ projectId });

async function userByEmail(email) {
  if (!email) throw new Error("--email is required");
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

async function verifySignup() {
  const user = await userByEmail(valueAfter("--email"));
  if (!user) throw new Error("Signup probe not found");
  await admin.auth().updateUser(user.uid, { emailVerified: true });
  console.log(`Verified signup uid=${user.uid}`);
}

async function deleteSignup() {
  const user = await userByEmail(valueAfter("--email"));
  if (!user) return;
  await db.collection("users").doc(user.uid).delete();
  await admin.auth().deleteUser(user.uid);
  console.log(`Deleted signup uid=${user.uid}`);
}

async function adminIdToken() {
  const apiKey = emulator ? "emulator-key" : process.env.FIREBASE_API_KEY;
  if (!apiKey) throw new Error("FIREBASE_API_KEY is required for staging cleanup");
  const baseUrl = emulator
    ? "http://127.0.0.1:9099/identitytoolkit.googleapis.com"
    : "https://identitytoolkit.googleapis.com";
  const response = await fetch(
    `${baseUrl}/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: emulator ? "admin@test.it" : "test.staging@example.com",
        password: "test1234",
        returnSecureToken: true,
      }),
    },
  );
  const payload = await response.json();
  if (!response.ok || !payload.idToken) {
    throw new Error(`Admin sign-in failed: ${JSON.stringify(payload)}`);
  }
  return payload.idToken;
}

async function deleteCourseViaCallable(courseId, idToken) {
  const url = emulator
    ? `http://127.0.0.1:5001/${projectId}/europe-west8/deleteCourse`
    : `https://europe-west8-${projectId}.cloudfunctions.net/deleteCourse`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ data: { courseId } }),
  });
  const payload = await response.json();
  if (!response.ok || payload.error) {
    throw new Error(
      `deleteCourse(${courseId}) failed: ${JSON.stringify(payload)}`,
    );
  }
}

async function cleanupCourses() {
  const namespace = valueAfter("--namespace");
  const prefix = namespace ? `[TEST:${namespace}]` : "[TEST:";
  const courses = await db.collection("courses").get();
  const ids = courses.docs
    .filter((doc) => String(doc.data().name || "").startsWith(prefix))
    .map((doc) => doc.id);
  if (ids.length === 0) return;
  const idToken = await adminIdToken();
  for (const id of ids) await deleteCourseViaCallable(id, idToken);
  console.log(`Deleted ${ids.length} E2E course(s) with prefix ${prefix}`);
}

// ---------------------------------------------------------------------------
// Matrice E2E enrollment
// ---------------------------------------------------------------------------

const MATRIX_PASSWORD = "test1234";

function requiredNamespace() {
  const namespace = valueAfter("--namespace");
  if (!namespace || !namespace.trim()) {
    throw new Error("--namespace is required for enrollment matrix fixtures");
  }
  return namespace.trim();
}

function matrixSlug(namespace) {
  const slug = namespace
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  if (!slug) throw new Error("--namespace contains no usable characters");
  return slug;
}

function matrixUid(namespace, key) {
  return `e2e_matrix_${matrixSlug(namespace)}_${key}`;
}

function matrixEmail(namespace, key) {
  return `e2e.matrix+${matrixSlug(namespace)}.${key}@example.com`;
}

function matrixCourseId(namespace, key) {
  return `e2e_matrix_${matrixSlug(namespace)}_course_${key}`;
}

function romeParts(date) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  return Object.fromEntries(
    parts
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, Number(part.value)]),
  );
}

/// Converts a Europe/Rome wall-clock to UTC without relying on host timezone.
function romeWallClockMillis(year, month, day, hour, minute = 0) {
  const wallClock = Date.UTC(year, month - 1, day, hour, minute, 0);
  let utc = wallClock;
  // Two iterations account for a possible DST transition near the target day.
  for (let i = 0; i < 2; i += 1) {
    const shown = romeParts(new Date(utc));
    const shownAsUtc = Date.UTC(
      shown.year,
      shown.month - 1,
      shown.day,
      shown.hour,
      shown.minute,
      shown.second,
    );
    utc = wallClock - (shownAsUtc - utc);
  }
  return utc;
}

/// Same slot used by integration_test/helpers/seed.dart: +8 days, 18:00 Rome.
function matrixSlot() {
  const reference = romeParts(new Date());
  const wallDate = new Date(
    Date.UTC(reference.year, reference.month - 1, reference.day + 8, 18),
  );
  return romeWallClockMillis(
    wallDate.getUTCFullYear(),
    wallDate.getUTCMonth() + 1,
    wallDate.getUTCDate(),
    18,
  );
}

async function upsertMatrixAuth(uid, email) {
  try {
    await admin.auth().updateUser(uid, {
      email,
      password: MATRIX_PASSWORD,
      emailVerified: true,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await admin.auth().createUser({
      uid,
      email,
      password: MATRIX_PASSWORD,
      emailVerified: true,
    });
  }
}

function matrixUser(namespace, key, extra = {}) {
  const uid = matrixUid(namespace, key);
  return {
    uid,
    email: matrixEmail(namespace, key),
    name: "E2E",
    lastName: `Matrix ${key}`,
    role: "User",
    courses: [],
    tipologiaIscrizione: null,
    entrateDisponibili: null,
    entrateSettimanali: null,
    fineIscrizione: null,
    isActive: true,
    isAnonymous: false,
    createdAt: Timestamp.now(),
    certificatoScadenza: Timestamp.fromMillis(Date.now() + 365 * 86400000),
    numeroTelefono: null,
    tipologiaCorsoTags: [],
    cancelledEnrollments: [],
    regolamentoAccettatoIl: Timestamp.now(),
    waitlistCourses: [],
    emailNotificationsEnabled: false,
    pushNotificationsEnabled: false,
    activeSubscriptions: [],
    e2eNamespace: namespace,
    e2eEnrollmentMatrix: true,
    ...extra,
  };
}

function matrixSubscription(namespace, userId, key, over = {}) {
  const id = `${matrixUid(namespace, userId)}_sub_${key}`;
  const base = {
    planKey: "open_2x_3m",
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency: 2,
    remainingEntries: null,
    startDate: Timestamp.fromMillis(Date.now() - 86400000),
    endDate: Timestamp.fromMillis(Date.now() + 90 * 86400000),
    ...over,
  };
  return {
    id,
    userId: matrixUid(namespace, userId),
    snapshot: { id, ...base },
    doc: {
      userId: matrixUid(namespace, userId),
      e2eNamespace: namespace,
      e2eEnrollmentMatrix: true,
      ...base,
    },
  };
}

function matrixCourse(namespace, key, startMillis, over = {}) {
  const id = matrixCourseId(namespace, key);
  return {
    id,
    uid: id,
    name: `[TEST:${namespace}] Matrix ${key}`,
    startDate: Timestamp.fromMillis(startMillis),
    endDate: Timestamp.fromMillis(startMillis + 60 * 60000),
    capacity: 10,
    subscribed: 0,
    tags: ["Open"],
    waitlist: [],
    reminderEnabled: false,
    waitlistEnabled: true,
    e2eNamespace: namespace,
    e2eEnrollmentMatrix: true,
    ...over,
  };
}

async function prepareEnrollmentMatrix() {
  const namespace = requiredNamespace();
  await cleanupEnrollmentMatrix(namespace);
  const slot = matrixSlot();
  const expiresBeforeCourse = Timestamp.fromMillis(slot - 1);

  const courses = [
    matrixCourse(namespace, "open-used", slot),
    matrixCourse(namespace, "open-first", slot + 60000),
    matrixCourse(namespace, "open-second", slot + 2 * 60000),
    matrixCourse(namespace, "hyrox-active", slot + 3 * 60000, { tags: ["Hyrox"] }),
    matrixCourse(namespace, "pt-active", slot + 4 * 60000, { tags: ["Personal Trainer"] }),
    matrixCourse(namespace, "pack-first", slot + 5 * 60000),
    matrixCourse(namespace, "pack-second", slot + 6 * 60000),
    matrixCourse(namespace, "trial-active", slot + 7 * 60000),
    matrixCourse(namespace, "temporal-active", slot + 8 * 60000),
    matrixCourse(namespace, "waitlist-active", slot + 9 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "open-expired", slot + 10 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "hyrox-expired", slot + 11 * 60000, {
      tags: ["Hyrox"],
      capacity: 1,
      subscribed: 1,
    }),
    matrixCourse(namespace, "pt-expired", slot + 12 * 60000, {
      tags: ["Personal Trainer"],
      capacity: 1,
      subscribed: 1,
    }),
    matrixCourse(namespace, "pack-expired", slot + 13 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "trial-expired", slot + 14 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "temporal-expired", slot + 15 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "open-limit-used", slot + 16 * 60000),
    matrixCourse(namespace, "open-limit-full", slot + 17 * 60000, { capacity: 1, subscribed: 1 }),
    matrixCourse(namespace, "pack-exhausted-full", slot + 18 * 60000, { capacity: 1, subscribed: 1 }),
  ];
  const course = Object.fromEntries(courses.map((entry) => [entry.id, entry]));

  const users = [
    matrixUser(namespace, "open", { courses: [course[matrixCourseId(namespace, "open-used")].uid] }),
    matrixUser(namespace, "hyrox"),
    matrixUser(namespace, "pt"),
    matrixUser(namespace, "pack", {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 1,
      fineIscrizione: Timestamp.fromMillis(slot + 90 * 86400000),
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "trial", {
      tipologiaIscrizione: "ABBONAMENTO_PROVA",
      entrateDisponibili: 1,
      fineIscrizione: Timestamp.fromMillis(slot + 90 * 86400000),
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "temporal", {
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 2,
      fineIscrizione: Timestamp.fromMillis(slot + 90 * 86400000),
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "waitlist"),
    matrixUser(namespace, "open-expired"),
    matrixUser(namespace, "hyrox-expired"),
    matrixUser(namespace, "pt-expired"),
    matrixUser(namespace, "pack-expired", {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 1,
      fineIscrizione: expiresBeforeCourse,
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "trial-expired", {
      tipologiaIscrizione: "ABBONAMENTO_PROVA",
      entrateDisponibili: 1,
      fineIscrizione: expiresBeforeCourse,
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "temporal-expired", {
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 2,
      fineIscrizione: expiresBeforeCourse,
      tipologiaCorsoTags: ["Open"],
    }),
    matrixUser(namespace, "open-limit", {
      courses: [course[matrixCourseId(namespace, "open-limit-used")].uid],
    }),
    matrixUser(namespace, "pack-exhausted", {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 0,
      fineIscrizione: Timestamp.fromMillis(slot + 90 * 86400000),
      tipologiaCorsoTags: ["Open"],
    }),
  ];

  const subscriptions = [
    matrixSubscription(namespace, "open", "open", {}),
    matrixSubscription(namespace, "hyrox", "hyrox", {
      planKey: "hyrox_10i_3m",
      family: "HYROX",
      billingMode: "ENTRIES",
      courseTypeTags: ["Hyrox"],
      weeklyFrequency: null,
      remainingEntries: 1,
    }),
    matrixSubscription(namespace, "pt", "pt", {
      planKey: "pt_10i_3m",
      family: "PT",
      billingMode: "ENTRIES",
      courseTypeTags: ["Personal Trainer"],
      weeklyFrequency: null,
      remainingEntries: 1,
    }),
    matrixSubscription(namespace, "waitlist", "open", {}),
    matrixSubscription(namespace, "open-expired", "open", { endDate: expiresBeforeCourse }),
    matrixSubscription(namespace, "hyrox-expired", "hyrox", {
      planKey: "hyrox_10i_3m",
      family: "HYROX",
      billingMode: "ENTRIES",
      courseTypeTags: ["Hyrox"],
      weeklyFrequency: null,
      remainingEntries: 1,
      endDate: expiresBeforeCourse,
    }),
    matrixSubscription(namespace, "pt-expired", "pt", {
      planKey: "pt_10i_3m",
      family: "PT",
      billingMode: "ENTRIES",
      courseTypeTags: ["Personal Trainer"],
      weeklyFrequency: null,
      remainingEntries: 1,
      endDate: expiresBeforeCourse,
    }),
    matrixSubscription(namespace, "open-limit", "open", { weeklyFrequency: 1 }),
  ];

  const snapshotsByUid = new Map();
  for (const subscription of subscriptions) {
    const list = snapshotsByUid.get(subscription.userId) || [];
    list.push(subscription.snapshot);
    snapshotsByUid.set(subscription.userId, list);
  }
  for (const user of users) {
    user.activeSubscriptions = snapshotsByUid.get(user.uid) || [];
    await upsertMatrixAuth(user.uid, user.email);
    await db.collection("users").doc(user.uid).set(user);
  }
  for (const subscription of subscriptions) {
    await db.collection("subscriptions").doc(subscription.id).set(subscription.doc);
  }
  for (const entry of courses) {
    await db.collection("courses").doc(entry.uid).set(entry);
  }

  console.log(
    `Prepared enrollment matrix namespace=${namespace} (${users.length} users, ${courses.length} courses)`,
  );
}

async function cleanupEnrollmentMatrix(namespace) {
  const all = namespace === null;
  const field = all ? "e2eEnrollmentMatrix" : "e2eNamespace";
  const value = all ? true : namespace;
  const courseSnap = await db.collection("courses").where(field, "==", value).get();
  if (!courseSnap.empty) {
    const idToken = await adminIdToken();
    for (const doc of courseSnap.docs) await deleteCourseViaCallable(doc.id, idToken);
  }

  const subscriptionSnap = await db.collection("subscriptions").where(field, "==", value).get();
  for (const doc of subscriptionSnap.docs) await doc.ref.delete();

  const userSnap = await db.collection("users").where(field, "==", value).get();
  for (const doc of userSnap.docs) {
    await doc.ref.delete();
    try {
      await admin.auth().deleteUser(doc.id);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  }
  console.log(
    `Cleaned enrollment matrix namespace=${all ? "all" : namespace} (${courseSnap.size} courses, ${subscriptionSnap.size} subscriptions, ${userSnap.size} users)`,
  );
}

async function main() {
  if (command === "verify-signup") return verifySignup();
  if (command === "delete-signup") return deleteSignup();
  if (command === "cleanup-courses") return cleanupCourses();
  if (command === "prepare-enrollment-matrix") return prepareEnrollmentMatrix();
  if (command === "cleanup-enrollment-matrix") {
    return cleanupEnrollmentMatrix(args.includes("--all") ? null : requiredNamespace());
  }
  throw new Error(
    "Command must be verify-signup, delete-signup, cleanup-courses, prepare-enrollment-matrix, or cleanup-enrollment-matrix",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("E2E admin command failed:", error);
    process.exit(1);
  });
