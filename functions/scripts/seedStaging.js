/* eslint-disable no-console */
// Idempotent seed for the isolated Firebase staging project.
// Usage: STAGING_PROJECT_ID=fit-rope-staging node functions/scripts/seedStaging.js --confirm-staging

if (!process.argv.includes("--confirm-staging")) {
  throw new Error("Refusing to seed without --confirm-staging");
}

const projectId = process.env.STAGING_PROJECT_ID;
if (
  !projectId ||
  !projectId.includes("staging") ||
  projectId === "fit-rope-app-1f575"
) {
  throw new Error(
    "STAGING_PROJECT_ID must name a non-production staging project",
  );
}

const admin = require("firebase-admin");
const { Firestore, Timestamp } = require("@google-cloud/firestore");
const { planByKey } = require("../lib/enrollment/plansCatalog");
const {
  buildSubscriptionFromPlan,
  recordToDoc,
  recordToSnapshotEntry,
} = require("../lib/enrollment/subscription");

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

const appOptions = { projectId };
const credential = stagingCredential();
if (credential) appOptions.credential = credential;
admin.initializeApp(appOptions);
const db = new Firestore({ projectId });
const PASSWORD = "test1234";
const MEMBER_UID = "stg_member";
const MEMBER2_UID = "stg_member2";
const MEMBER_SUBSCRIPTIONS = [
  {
    planKey: "open_3x_3m",
    subscriptionId: "stg_member_open_3x_3m",
  },
  {
    planKey: "hyrox_10i_3m",
    subscriptionId: "stg_member_hyrox_10i_3m",
  },
  {
    planKey: "pt_10i_3m",
    subscriptionId: "stg_member_pt_10i_3m",
  },
];

function timestampInDays(days) {
  return Timestamp.fromMillis(Date.now() + days * 86400000);
}

function user(uid, email, role, extra = {}) {
  const lastNames = {
    stg_admin: "Admin",
    stg_trainer: "Trainer",
    stg_member: "Member Uno",
    stg_member2: "Member Due",
  };
  return {
    uid,
    email,
    name: "Staging",
    lastName: lastNames[uid] || role,
    role,
    courses: [],
    tipologiaIscrizione: null,
    entrateDisponibili: null,
    entrateSettimanali: null,
    fineIscrizione: null,
    isActive: true,
    isAnonymous: false,
    createdAt: Timestamp.now(),
    certificatoScadenza: timestampInDays(180),
    numeroTelefono: null,
    tipologiaCorsoTags: role === "Admin" ? ["Tutti i corsi"] : ["Open"],
    cancelledEnrollments: [],
    regolamentoAccettatoIl: Timestamp.now(),
    waitlistCourses: [],
    emailNotificationsEnabled: true,
    pushNotificationsEnabled: false,
    activeSubscriptions: [],
    ...extra,
  };
}

async function upsertAuth(uid, email, displayName) {
  try {
    await admin.auth().getUser(uid);
    await admin.auth().updateUser(uid, {
      email,
      password: PASSWORD,
      displayName,
      emailVerified: true,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    await admin.auth().createUser({
      uid,
      email,
      password: PASSWORD,
      displayName,
      emailVerified: true,
    });
  }
}

async function ensureSubscription(planKey, subscriptionId, userId = MEMBER_UID) {
  const plan = planByKey(planKey);
  if (!plan) throw new Error(`Missing ${planKey} plan`);
  if (!subscriptionId || typeof subscriptionId !== "string") {
    throw new Error(`Missing subscriptionId for ${planKey}`);
  }

  const ref = db.collection("subscriptions").doc(subscriptionId);
  const record = buildSubscriptionFromPlan(plan, Date.now() - 86400000);
  await ref.set(recordToDoc(record, userId, "staging-seed"));
  return recordToSnapshotEntry({ ...record, id: ref.id });
}

async function main() {
  const users = [
    ["stg_admin", "test.staging@example.com", "Admin"],
    ["stg_trainer", "trainer.staging@example.com", "Trainer"],
    [MEMBER_UID, "member.staging@example.com", "User"],
    [MEMBER2_UID, "member2.staging@example.com", "User"],
    ["stg_disabled", "disabled.staging@example.com", "User"],
  ];

  for (const [uid, email, role] of users) {
    await upsertAuth(uid, email, `Staging ${role}`);
    await db
      .collection("users")
      .doc(uid)
      .set(
        user(uid, email, role, {
          isActive: uid !== "stg_disabled",
        }),
        { merge: true },
      );
  }

  const subscriptions = await Promise.all(
    MEMBER_SUBSCRIPTIONS.map(({ planKey, subscriptionId }) =>
      ensureSubscription(planKey, subscriptionId),
    ),
  );
  await db
    .collection("users")
    .doc(MEMBER_UID)
    .set(
      {
        activeSubscriptions: subscriptions,
        tipologiaCorsoTags: [],
        waitlistCourses: ["stg_open_full"],
      },
      { merge: true },
    );

  const member2Subscription = await ensureSubscription(
    "open_3x_3m",
    "stg_member2_open_3x_3m",
    MEMBER2_UID,
  );
  await db.collection("users").doc(MEMBER2_UID).set(
    {
      activeSubscriptions: [member2Subscription],
      tipologiaCorsoTags: [],
    },
    { merge: true },
  );

  const start = new Date(Date.now() + 3 * 86400000);
  start.setUTCHours(18, 0, 0, 0);
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const courses = [
    {
      id: "stg_open",
      name: "[STAGING] Open",
      tags: ["Open"],
      capacity: 10,
      subscribed: 0,
    },
    {
      id: "stg_hyrox",
      name: "[STAGING] Hyrox",
      tags: ["Hyrox"],
      capacity: 8,
      subscribed: 0,
    },
    {
      id: "stg_pt",
      name: "[STAGING] Personal Training",
      tags: ["Personal Trainer"],
      capacity: 1,
      subscribed: 0,
    },
    {
      id: "stg_open_full",
      name: "[STAGING] Open waitlist",
      tags: ["Open"],
      capacity: 1,
      subscribed: 1,
      waitlist: [MEMBER_UID],
    },
  ];
  for (const course of courses) {
    await db
      .collection("courses")
      .doc(course.id)
      .set(
        {
          uid: course.id,
          name: course.name,
          startDate: Timestamp.fromDate(start),
          endDate: Timestamp.fromDate(end),
          capacity: course.capacity,
          subscribed: course.subscribed,
          trainerId: "stg_trainer",
          tags: course.tags,
          sala: course.tags.includes("Hyrox") ? "Sala 2" : "Sala 1",
          waitlist: course.waitlist ?? [],
          reminderEnabled: true,
          waitlistEnabled: true,
        },
        { merge: true },
      );
  }

  console.log(`Staging seed complete for ${projectId}. Password: ${PASSWORD}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Staging seed failed:", error);
    process.exit(1);
  });
