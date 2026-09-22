#!/usr/bin/env node
/* eslint-disable no-console */

// Audit conservativo dei profili gia' V2 ma senza marker di versione.
const path = require("path");
const { createRequire } = require("module");
const req = createRequire(path.resolve(__dirname, "../functions/package.json"));
const admin = req("firebase-admin");
const { canReconcileSubscriptionModel } = require("../functions/lib/enrollment/provisioning");

const args = Object.fromEntries(process.argv.slice(2).map((arg) => {
  const [key, value] = arg.replace(/^--/, "").split("=", 2);
  return [key, value ?? true];
}));
if (typeof args.project !== "string" || !args.project) throw new Error("--project obbligatorio");
const apply = args.apply === true;
if (apply && args["confirm-project"] !== args.project) {
  throw new Error("--apply richiede --confirm-project uguale al progetto");
}
admin.initializeApp({ projectId: args.project });
const db = admin.firestore();

async function main() {
  const [users, subscriptions] = await Promise.all([
    db.collection("users").get(), db.collection("subscriptions").get(),
  ]);
  const byUser = new Map();
  for (const doc of subscriptions.docs) {
    const userId = doc.data().userId;
    if (typeof userId === "string") {
      if (!byUser.has(userId)) byUser.set(userId, []);
      byUser.get(userId).push({ id: doc.id, ...doc.data() });
    }
  }
  const safe = [];
  const manual = [];
  for (const doc of users.docs) {
    const data = doc.data();
    if ((data.subscriptionModelVersion ?? 1) >= 2 || !Array.isArray(data.activeSubscriptions) || data.activeSubscriptions.length === 0) continue;
    const subs = byUser.get(doc.id) ?? [];
    const snapshotIds = new Set(data.activeSubscriptions.map((item) => item?.id));
    const subscriptionIds = new Set(subs.map((item) => item.id));
    const snapshotMatches = snapshotIds.size === subscriptionIds.size &&
      [...snapshotIds].every((id) => subscriptionIds.has(id));
    (canReconcileSubscriptionModel(data, subs) && snapshotMatches ? safe : manual).push(doc.id);
  }
  console.log(JSON.stringify({ project: args.project, safe, manual }));
  if (apply) await Promise.all(safe.map((id) => db.collection("users").doc(id).update({ subscriptionModelVersion: 2 })));
  if (manual.length) process.exitCode = 2;
}
main().catch((error) => { console.error(error.message); process.exitCode = 1; });
