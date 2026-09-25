#!/usr/bin/env node
/* Guarded Firestore/Auth operations for the PRD -> Staging rehearsal. */
"use strict";

const fs = require("node:fs");
const admin = require("../functions/node_modules/firebase-admin");
const { planByKey } = require("../functions/lib/enrollment/plansCatalog");
const {
  buildSubscriptionFromPlan,
  recordToDoc,
  recordToSnapshotEntry,
} = require("../functions/lib/enrollment/subscription");

const PROJECT = "fit-rope-staging";
const QA_UIDS = new Set([
  "dev_admin", "dev_trainer", "dev_member_open_2x",
  "dev_member_open_unlimited", "dev_member_pt_entries",
]);
const args = Object.fromEntries(process.argv.slice(2).map((raw) => {
  const [key, ...rest] = raw.split("=");
  return [key.replace(/^--/, ""), rest.length ? rest.join("=") : true];
}));
const action = process.argv[2];
if (args.project !== PROJECT) {
  throw new Error(`Only ${PROJECT} is permitted`);
}
if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();

async function listAuthUsers() {
  const users = [];
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    users.push(...page.users);
    token = page.pageToken;
  } while (token);
  return users;
}

async function auditAuthCollisions() {
  const users = await listAuthUsers();
  const unexpected = [];
  for (const user of users) {
    if (QA_UIDS.has(user.uid)) continue;
    if ((await db.collection("users").doc(user.uid).get()).exists) {
      unexpected.push(user.uid);
    }
  }
  console.log(JSON.stringify({ authUsers: users.length, unexpectedCollisions: unexpected }, null, 2));
  if (unexpected.length) process.exitCode = 2;
}

async function verifyEmpty() {
  const collections = await db.listCollections();
  const nonempty = [];
  for (const coll of collections) {
    if (!(await coll.limit(1).get()).empty) nonempty.push(coll.id);
  }
  console.log(JSON.stringify({ rootCollections: collections.length, nonempty }, null, 2));
  if (nonempty.length) process.exitCode = 2;
}

async function wipe() {
  if (args["confirm-project"] !== PROJECT) throw new Error("Explicit staging confirmation required");
  for (const key of ["staging-backup-sha256", "prod-backup-sha256"]) {
    if (!/^[a-f0-9]{64}$/.test(args[key] || "")) throw new Error(`${key} required`);
  }
  const collections = await db.listCollections();
  for (const coll of collections) {
    const docs = await coll.listDocuments();
    console.log(`Deleting ${coll.id}: ${docs.length} roots (including descendants)`);
    for (const ref of docs) await db.recursiveDelete(ref);
  }
  await verifyEmpty();
}

async function provision() {
  if (args["confirm-project"] !== PROJECT) throw new Error("Explicit staging confirmation required");
  const path = args.input;
  if (!path || !fs.existsSync(path)) throw new Error("Private --input file required");
  const stat = fs.statSync(path);
  if ((stat.mode & 0o077) !== 0) throw new Error("Private input must be mode 0600");
  const payload = JSON.parse(fs.readFileSync(path, "utf8"));
  if (payload.projectId !== PROJECT || !Array.isArray(payload.users) || payload.users.length !== 5) {
    throw new Error("Invalid QA input manifest");
  }
  const seen = new Set();
  const existingAuth = new Map((await listAuthUsers()).map((user) => [user.uid, user]));
  for (const user of payload.users) {
    if (!QA_UIDS.has(user.uid) || seen.has(user.uid) ||
        !["Admin", "Trainer", "User"].includes(user.role) ||
        typeof user.email !== "string" || typeof user.password !== "string" ||
        user.password.length < 6 || user.authDisabled !== false ||
        (user.role === "User" ? !planByKey(user.planKey) : user.planKey !== null)) {
      throw new Error("Invalid QA account entry");
    }
    seen.add(user.uid);
    if ((await db.collection("users").doc(user.uid).get()).exists) {
      throw new Error(`QA Firestore document already exists: ${user.uid}`);
    }
    const emailOwner = [...existingAuth.values()].find((entry) =>
      entry.email?.toLowerCase() === user.email.toLowerCase());
    if (emailOwner && emailOwner.uid !== user.uid) {
      throw new Error(`Email belongs to another UID: ${user.email}`);
    }
  }
  for (const user of payload.users) {
    const authFields = { email: user.email, password: user.password,
      disabled: false, emailVerified: true };
    if (existingAuth.has(user.uid)) await auth.updateUser(user.uid, authFields);
    else await auth.createUser({ uid: user.uid, ...authFields });
    const userRef = db.collection("users").doc(user.uid);
    const plan = user.planKey ? planByKey(user.planKey) : null;
    const subRef = plan ? db.collection("subscriptions").doc() : null;
    const record = plan ? buildSubscriptionFromPlan(plan, Date.now()) : null;
    const [name, lastName] = user.uid === "dev_admin" ? ["Admin", "Develop"] :
      user.uid === "dev_trainer" ? ["Trainer", "Develop"] :
      ["Utente", user.uid.split("_").at(-1)];
    await db.runTransaction(async (tx) => {
      const profile = {
        uid: user.uid, email: user.email, name, lastName, role: user.role,
        courses: [], isActive: true, isAnonymous: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        numeroTelefono: null, cancelledEnrollments: [], waitlistCourses: [],
        emailNotificationsEnabled: true, pushNotificationsEnabled: false,
        activeSubscriptions: record ? [recordToSnapshotEntry({ ...record, id: subRef.id })] : [],
        subscriptionModelVersion: 2,
      };
      tx.create(userRef, profile);
      if (record) tx.create(subRef, recordToDoc(record, user.uid, "dev_admin"));
    });
    console.log(`Provisioned ${user.uid}: ${user.role}${plan ? ` / ${plan.key}` : ""}`);
  }
}

(async () => {
  if (action === "audit-auth-collisions") await auditAuthCollisions();
  else if (action === "verify-empty") await verifyEmpty();
  else if (action === "wipe") await wipe();
  else if (action === "provision") await provision();
  else throw new Error("Action: audit-auth-collisions | verify-empty | wipe | provision");
})().catch((err) => { console.error(err.message); process.exitCode = 1; });
