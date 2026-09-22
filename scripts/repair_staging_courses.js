#!/usr/bin/env node
/* eslint-disable no-console */

// Ripara esclusivamente il dataset sintetico staging. Sicuro di default:
// legge e stampa il piano, scrive solo con --apply --confirm-project espliciti.
const path = require("path");
const { createRequire } = require("module");
const requireFromFunctions = createRequire(path.resolve(__dirname, "../functions/package.json"));
const { Firestore, FieldValue } = requireFromFunctions("@google-cloud/firestore");
const { buildCourseDocument } = require("../functions/lib/enrollment/courseDocument");

const args = Object.fromEntries(process.argv.slice(2).map((arg) => {
  const [key, value] = arg.replace(/^--/, "").split("=", 2);
  return [key, value ?? true];
}));
const project = args.project;
if (project !== "fit-rope-staging") {
  throw new Error("Questo repair accetta esclusivamente --project=fit-rope-staging");
}
const apply = args.apply === true;
if (apply && args["confirm-project"] !== project) {
  throw new Error("--apply richiede --confirm-project=fit-rope-staging");
}
// Firebase Admin 12 does not recognize the external-account credentials file
// emitted by google-github-actions/auth@v3. The Google Cloud Firestore client
// does, so use it directly for CI repair jobs (and keep ADC for local/service
// account execution). This also avoids putting a long-lived key in Actions.
const db = new Firestore({ projectId: project });

const future = new Date(Date.now() + 7 * 86400000);
const base = (uid, courseType, tag) => {
  const document = buildCourseDocument({
  uid, name: `[STAGING] repair ${uid}`, startDate: future,
  endDate: new Date(future.getTime() + 3600000), capacity: 10, subscribed: 0,
  trainerId: "stg_trainer", courseType, tag, waitlist: [],
  reminderEnabled: true, waitlistEnabled: true,
  });
  const { id, uid: canonicalUid, courseType: canonicalType, tag: canonicalTag,
    tags, courseModelV2 } = document;
  return { id, uid: canonicalUid, courseType: canonicalType, tag: canonicalTag,
    tags, courseModelV2 };
};
const targets = [
  ...["dev_open_1", "dev_open_2", "dev_open_3"].map((id) => [id, base(id, "open", null)]),
  ...["dev_hyrox_1", "dev_hyrox_2"].map((id) => [id, base(id, "open", "Hyrox")]),
  ...["dev_pt_1", "dev_pt_2"].map((id) => [id, base(id, "personal_trainer", "Personal Trainer")]),
];
const idsOnly = ["stg_open", "stg_hyrox", "stg_pt", "stg_open_full"];

async function updateIfPresent(id, patch) {
  const ref = db.collection("courses").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return console.log(`skip ${id}: assente`);
  console.log(`${apply ? "repair" : "would repair"} ${id}`);
  if (apply) await ref.set(patch, { merge: true });
}

async function main() {
  for (const [id, target] of targets) await updateIfPresent(id, target);
  for (const id of idsOnly) await updateIfPresent(id, { id, uid: id });
  await updateIfPresent("dev_hey_mamma", {
    id: "dev_hey_mamma", uid: "dev_hey_mamma", tags: ["Hey Mamma"],
    courseModelV2: false, courseType: FieldValue.delete(), tag: FieldValue.delete(),
  });
}
main().catch((error) => { console.error(error.message); process.exitCode = 1; });
