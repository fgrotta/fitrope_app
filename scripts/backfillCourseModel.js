#!/usr/bin/env node
/* eslint-disable no-console */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { createRequire } = require("module");
const requireFromFunctions = createRequire(
  path.resolve(__dirname, "../functions/package.json")
);
const admin = requireFromFunctions("firebase-admin");
const { Timestamp } = requireFromFunctions("firebase-admin/firestore");
const {
  transformCourse,
  targetMatchesCourse,
} = require("../functions/lib/migration/courseTransform");
const {
  transformUser,
  timestampMillis,
} = require("../functions/lib/migration/userTransform");
const {
  writePrivateCsv,
} = require("../functions/lib/migration/csv");

const USER_COLUMNS = [
  "run_id", "evaluated_at", "project_id", "document_id", "uid", "email",
  "name", "last_name", "numero_telefono", "role", "is_active", "created_at",
  "tipologia_iscrizione", "tipologia_corso_tags", "entrate_disponibili",
  "entrate_settimanali", "fine_iscrizione", "conversion_status", "reason_code",
  "reason_detail", "target_subscription_id", "target_plan_key", "target_family",
  "target_billing_mode", "target_course_type_tags", "target_weekly_frequency",
  "target_remaining_entries", "target_start_date", "target_end_date", "apply_status",
];

const COURSE_COLUMNS = [
  "run_id", "evaluated_at", "project_id", "document_id", "source_tags",
  "source_course_type", "source_course_model_v2", "conversion_status", "reason_code",
  "reason_detail", "target_course_type", "target_tag", "target_tags",
  "target_course_model_v2", "apply_status",
];

function parseArgs(argv) {
  const args = {};
  for (const value of argv) {
    if (!value.startsWith("--")) throw new Error(`Argomento inatteso: ${value}`);
    const index = value.indexOf("=");
    if (index === -1) args[value.slice(2)] = true;
    else args[value.slice(2, index)] = value.slice(index + 1);
  }
  const modes = ["dry-run", "apply", "verify"].filter((key) => args[key]);
  if (modes.length > 1) throw new Error("Scegliere una sola modalita");
  args.mode = modes[0] || "dry-run";
  args.scope = args.scope || "all";
  if (!["courses", "users", "all"].includes(args.scope)) {
    throw new Error("--scope deve essere courses, users o all");
  }
  if (typeof args.project !== "string" || !args.project.trim()) {
    throw new Error("--project e obbligatorio");
  }
  return args;
}

function normalize(value) {
  if (value === undefined) return { __undefined: true };
  if (value === null || typeof value !== "object") return value;
  if (typeof value.toMillis === "function") return { __timestamp: value.toMillis() };
  if (value instanceof Date) return { __date: value.toISOString() };
  if (Array.isArray(value)) return value.map(normalize);
  const result = {};
  for (const key of Object.keys(value).sort()) result[key] = normalize(value[key]);
  return result;
}

function fingerprint(value) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(normalize(value)))
    .digest("hex");
}

function courseSource(data) {
  return {
    courseModelV2: data.courseModelV2,
    courseType: data.courseType,
    tag: data.tag,
    tags: data.tags,
  };
}

function userSource(data) {
  return {
    role: data.role,
    tipologiaCorsoTags: data.tipologiaCorsoTags,
    tipologiaIscrizione: data.tipologiaIscrizione,
    entrateSettimanali: data.entrateSettimanali,
    fineIscrizione: data.fineIscrizione,
  };
}

function iso(value) {
  const millis = timestampMillis(value);
  return millis === null ? "" : new Date(millis).toISOString();
}

function runIdNow() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function safeReportDir(repoRoot, requested, runId) {
  const base = path.resolve(repoRoot, ".context", "migrations");
  const reportDir = requested
    ? path.resolve(repoRoot, requested)
    : path.join(base, runId);
  if (reportDir !== base && !reportDir.startsWith(`${base}${path.sep}`)) {
    throw new Error("I report con dati personali devono restare sotto .context/migrations");
  }
  fs.mkdirSync(reportDir, { recursive: true, mode: 0o700 });
  fs.chmodSync(reportDir, 0o700);
  return reportDir;
}

function subscriptionComparable(target) {
  return {
    userId: target.userId,
    createdBy: target.createdBy,
    planKey: target.planKey,
    family: target.family,
    billingMode: target.billingMode,
    courseTypeTags: target.courseTypeTags,
    weeklyFrequency: target.weeklyFrequency,
    remainingEntries: target.remainingEntries,
    startDateMillis: target.startDateMillis,
    endDateMillis: target.endDateMillis,
  };
}

function existingSubscriptionComparable(data) {
  return {
    userId: data.userId,
    createdBy: data.createdBy,
    planKey: data.planKey,
    family: data.family,
    billingMode: data.billingMode,
    courseTypeTags: data.courseTypeTags,
    weeklyFrequency: data.weeklyFrequency ?? null,
    remainingEntries: data.remainingEntries ?? null,
    startDateMillis: timestampMillis(data.startDate),
    endDateMillis: timestampMillis(data.endDate),
  };
}

function subscriptionMatches(data, target) {
  return JSON.stringify(normalize(existingSubscriptionComparable(data))) ===
    JSON.stringify(normalize(subscriptionComparable(target)));
}

function snapshotMatchesTarget(userData, target, evaluatedAtMillis) {
  const raw = userData.activeSubscriptions;
  const entries = Array.isArray(raw) ? raw : [];
  const current = entries.find((entry) => entry && entry.id === target.id);
  if (!current) return target.endDateMillis < evaluatedAtMillis;
  const comparable = {
    planKey: current.planKey,
    family: current.family,
    billingMode: current.billingMode,
    courseTypeTags: current.courseTypeTags,
    weeklyFrequency: current.weeklyFrequency ?? null,
    remainingEntries: current.remainingEntries ?? null,
    startDateMillis: timestampMillis(current.startDate),
    endDateMillis: timestampMillis(current.endDate),
  };
  const expected = {
    planKey: target.planKey,
    family: target.family,
    billingMode: target.billingMode,
    courseTypeTags: target.courseTypeTags,
    weeklyFrequency: target.weeklyFrequency,
    remainingEntries: target.remainingEntries,
    startDateMillis: target.startDateMillis,
    endDateMillis: target.endDateMillis,
  };
  return JSON.stringify(normalize(comparable)) === JSON.stringify(normalize(expected));
}

function userReport(run, id, data, decision, applyStatus = "NOT_APPLIED") {
  const target = decision.target;
  return {
    run_id: run.runId,
    evaluated_at: new Date(run.evaluatedAtMillis).toISOString(),
    project_id: run.projectId,
    document_id: id,
    uid: data.uid ?? "",
    email: data.email ?? "",
    name: data.name ?? "",
    last_name: data.lastName ?? "",
    numero_telefono: data.numeroTelefono ?? "",
    role: data.role ?? "",
    is_active: data.isActive ?? "",
    created_at: iso(data.createdAt),
    tipologia_iscrizione: data.tipologiaIscrizione ?? "",
    tipologia_corso_tags: Array.isArray(data.tipologiaCorsoTags)
      ? data.tipologiaCorsoTags
      : [],
    entrate_disponibili: data.entrateDisponibili ?? "",
    entrate_settimanali: data.entrateSettimanali ?? "",
    fine_iscrizione: iso(data.fineIscrizione),
    conversion_status: decision.conversionStatus,
    reason_code: decision.reasonCode,
    reason_detail: decision.reasonDetail,
    target_subscription_id: target?.id ?? "",
    target_plan_key: target?.planKey ?? "",
    target_family: target?.family ?? "",
    target_billing_mode: target?.billingMode ?? "",
    target_course_type_tags: target?.courseTypeTags ?? [],
    target_weekly_frequency: target?.weeklyFrequency ?? "",
    target_remaining_entries: target?.remainingEntries ?? "",
    target_start_date: target ? new Date(target.startDateMillis).toISOString() : "",
    target_end_date: target ? new Date(target.endDateMillis).toISOString() : "",
    apply_status: applyStatus,
  };
}

function courseReport(run, id, data, decision, applyStatus = "NOT_APPLIED") {
  const target = decision.target;
  return {
    run_id: run.runId,
    evaluated_at: new Date(run.evaluatedAtMillis).toISOString(),
    project_id: run.projectId,
    document_id: id,
    source_tags: Array.isArray(data.tags) ? data.tags : [],
    source_course_type: data.courseType ?? "",
    source_course_model_v2: data.courseModelV2 ?? false,
    conversion_status: decision.conversionStatus,
    reason_code: decision.reasonCode,
    reason_detail: decision.reasonDetail,
    target_course_type: target?.courseType ?? "",
    target_tag: target?.tag ?? "",
    target_tags: target?.tags ?? [],
    target_course_model_v2: target?.courseModelV2 ?? "",
    apply_status: applyStatus,
  };
}

function writeJsonl(file, entries) {
  const content = entries.map((entry) => JSON.stringify(entry)).join("\n") + "\n";
  fs.writeFileSync(file, content, { encoding: "utf8", mode: 0o600 });
  fs.chmodSync(file, 0o600);
}

function readJsonl(file) {
  return fs
    .readFileSync(file, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

async function scan(db, run, scope) {
  const entries = [];
  const userRows = [];
  const courseRows = [];
  let subscriptions = [];
  let hyroxSnapshots = 0;
  if (scope === "users" || scope === "all") {
    subscriptions = (await db.collection("subscriptions").get()).docs;
  }
  const subsByUser = new Map();
  for (const doc of subscriptions) {
    const data = doc.data();
    const list = subsByUser.get(data.userId) || [];
    list.push({ id: doc.id, data });
    subsByUser.set(data.userId, list);
  }

  if (scope === "courses" || scope === "all") {
    const snapshot = await db.collection("courses").get();
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const decision = transformCourse(data);
      const entry = {
        version: 1,
        ...run,
        kind: "course",
        documentId: doc.id,
        sourceFingerprint: fingerprint(courseSource(data)),
        decision,
        report: courseReport(run, doc.id, data, decision),
      };
      entries.push(entry);
      courseRows.push(entry.report);
    }
  }

  if (scope === "users" || scope === "all") {
    const snapshot = await db.collection("users").get();
    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (Array.isArray(data.activeSubscriptions)) {
        hyroxSnapshots += data.activeSubscriptions.filter((subscription) =>
          subscription?.family === "HYROX" ||
          (typeof subscription?.planKey === "string" &&
            subscription.planKey.startsWith("hyrox_"))
        ).length;
      }
      const decision = transformUser(doc.id, data, run.evaluatedAtMillis);
      if (decision.target) {
        const existing = subsByUser.get(doc.id) || [];
        const deterministic = existing.find((sub) => sub.id === decision.target.id);
        const otherOpen = existing.some(
          (sub) => sub.id !== decision.target.id && sub.data.family === "OPEN"
        );
        if (deterministic &&
            subscriptionMatches(deterministic.data, decision.target) &&
            snapshotMatchesTarget(data, decision.target, run.evaluatedAtMillis) &&
            !otherOpen) {
          decision.conversionStatus = "ALREADY_APPLIED";
          decision.reasonCode = "ALREADY_APPLIED";
          decision.reasonDetail = "subscription deterministica gia identica";
        } else if (deterministic || existing.some((sub) => sub.data.family === "OPEN")) {
          decision.conversionStatus = "TARGET_CONFLICT";
          decision.reasonCode = "EXISTING_SUBSCRIPTION_CONFLICT";
          decision.reasonDetail = "esiste gia una subscription OPEN diversa";
        }
      }
      const entry = {
        version: 1,
        ...run,
        kind: "user",
        documentId: doc.id,
        sourceFingerprint: fingerprint(userSource(data)),
        decision,
        report: userReport(run, doc.id, data, decision),
      };
      entries.push(entry);
      userRows.push(entry.report);
    }
  }
  return { entries, userRows, courseRows, subscriptions, hyroxSnapshots };
}

function writeReports(reportDir, userRows, courseRows) {
  if (userRows.length > 0) {
    writePrivateCsv(path.join(reportDir, "users-migration-report.csv"), USER_COLUMNS, userRows);
  }
  if (courseRows.length > 0) {
    writePrivateCsv(
      path.join(reportDir, "courses-migration-report.csv"),
      COURSE_COLUMNS,
      courseRows
    );
  }
}

function summarize(entries) {
  const counts = {};
  for (const entry of entries) {
    const key = `${entry.kind}:${entry.decision.conversionStatus}`;
    counts[key] = (counts[key] || 0) + 1;
  }
  return counts;
}

function subscriptionDoc(target) {
  return {
    userId: target.userId,
    createdBy: target.createdBy,
    planKey: target.planKey,
    family: target.family,
    billingMode: target.billingMode,
    courseTypeTags: target.courseTypeTags,
    weeklyFrequency: target.weeklyFrequency,
    remainingEntries: target.remainingEntries,
    startDate: Timestamp.fromMillis(target.startDateMillis),
    endDate: Timestamp.fromMillis(target.endDateMillis),
    createdAt: Timestamp.fromMillis(target.createdAtMillis),
  };
}

function snapshotEntry(id, data) {
  return {
    id,
    planKey: data.planKey,
    family: data.family,
    billingMode: data.billingMode,
    courseTypeTags: data.courseTypeTags,
    weeklyFrequency: data.weeklyFrequency ?? null,
    remainingEntries: data.remainingEntries ?? null,
    startDate: data.startDate,
    endDate: data.endDate,
  };
}

async function applyManifest(db, entries) {
  const statuses = new Map();
  const writer = db.bulkWriter();
  const courseWrites = [];
  for (const entry of entries.filter((item) => item.kind === "course")) {
    if (!entry.decision.target || entry.decision.conversionStatus !== "CONVERTIBLE") {
      statuses.set(`course:${entry.documentId}`, "SKIPPED");
      continue;
    }
    const ref = db.collection("courses").doc(entry.documentId);
    const snap = await ref.get();
    if (!snap.exists) {
      statuses.set(`course:${entry.documentId}`, "SOURCE_DRIFT");
      continue;
    }
    const data = snap.data();
    if (targetMatchesCourse(data, entry.decision.target)) {
      statuses.set(`course:${entry.documentId}`, "ALREADY_APPLIED");
      continue;
    }
    if (data.courseModelV2 === true) {
      statuses.set(`course:${entry.documentId}`, "TARGET_CONFLICT");
      continue;
    }
    if (fingerprint(courseSource(data)) !== entry.sourceFingerprint) {
      statuses.set(`course:${entry.documentId}`, "SOURCE_DRIFT");
      continue;
    }
    const write = writer
      .update(ref, entry.decision.target, { lastUpdateTime: snap.updateTime })
      .then(() => {
        statuses.set(`course:${entry.documentId}`, "APPLIED");
      })
      .catch((error) => {
        if (error.code === 9 || error.code === "failed-precondition") {
          statuses.set(`course:${entry.documentId}`, "SOURCE_DRIFT");
          return;
        }
        throw error;
      });
    courseWrites.push(write);
  }
  await writer.close();
  await Promise.all(courseWrites);

  for (const entry of entries.filter((item) => item.kind === "user")) {
    const target = entry.decision.target;
    if (!target || entry.decision.conversionStatus !== "CONVERTIBLE") {
      statuses.set(`user:${entry.documentId}`, "SKIPPED");
      continue;
    }
    const status = await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(entry.documentId);
      const targetRef = db.collection("subscriptions").doc(target.id);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) return "SOURCE_DRIFT";
      const targetSnap = await tx.get(targetRef);
      if (targetSnap.exists && subscriptionMatches(targetSnap.data(), target)) {
        return snapshotMatchesTarget(
          userSnap.data(),
          target,
          entry.evaluatedAtMillis
        ) ? "ALREADY_APPLIED" : "TARGET_CONFLICT";
      }
      if (fingerprint(userSource(userSnap.data())) !== entry.sourceFingerprint) {
        return "SOURCE_DRIFT";
      }
      const subsSnap = await tx.get(
        db.collection("subscriptions").where("userId", "==", entry.documentId)
      );
      if (targetSnap.exists || subsSnap.docs.some((doc) => doc.data().family === "OPEN")) {
        return "TARGET_CONFLICT";
      }

      const targetData = subscriptionDoc(target);
      const all = subsSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
      all.push({ id: target.id, data: targetData });
      const activeSubscriptions = all
        .filter((item) => timestampMillis(item.data.endDate) >= entry.evaluatedAtMillis)
        .map((item) => snapshotEntry(item.id, item.data));
      tx.create(targetRef, targetData);
      tx.update(userRef, { activeSubscriptions });
      return "APPLIED";
    });
    statuses.set(`user:${entry.documentId}`, status);
  }
  return statuses;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = path.resolve(__dirname, "..");
  const runId = runIdNow();
  const reportDir = safeReportDir(repoRoot, args["report-dir"], runId);
  admin.initializeApp({ projectId: args.project });
  const db = admin.firestore();

  if (args.mode === "apply") {
    if (args["confirm-project"] !== args.project) {
      throw new Error("--confirm-project deve coincidere esattamente con --project");
    }
    if (typeof args.manifest !== "string") {
      throw new Error("--manifest e obbligatorio per --apply");
    }
    const manifestPath = path.resolve(repoRoot, args.manifest);
    const safeBase = path.resolve(repoRoot, ".context", "migrations");
    if (!manifestPath.startsWith(`${safeBase}${path.sep}`)) {
      throw new Error("Il manifest deve trovarsi sotto .context/migrations");
    }
    const entries = readJsonl(manifestPath);
    if (entries.length === 0 || entries.some((entry) => entry.projectId !== args.project)) {
      throw new Error("Manifest vuoto o riferito a un progetto diverso");
    }
    const scoped = entries.filter((entry) =>
      args.scope === "all" ||
      (args.scope === "courses" && entry.kind === "course") ||
      (args.scope === "users" && entry.kind === "user")
    );
    const statuses = await applyManifest(db, scoped);
    const reportRow = (entry, kind) => {
      const status = statuses.get(`${kind}:${entry.documentId}`);
      const row = { ...entry.report, apply_status: status };
      if (["SOURCE_DRIFT", "TARGET_CONFLICT", "ALREADY_APPLIED"].includes(status)) {
        row.conversion_status = status;
      }
      return row;
    };
    const userRows = scoped
      .filter((entry) => entry.kind === "user")
      .map((entry) => reportRow(entry, "user"));
    const courseRows = scoped
      .filter((entry) => entry.kind === "course")
      .map((entry) => reportRow(entry, "course"));
    writeReports(reportDir, userRows, courseRows);
    const counts = {};
    for (const status of statuses.values()) counts[status] = (counts[status] || 0) + 1;
    console.log(JSON.stringify({ mode: "apply", project: args.project, counts }));
    return;
  }

  const run = {
    runId,
    evaluatedAtMillis: Date.now(),
    projectId: args.project,
    scope: args.scope,
  };
  const result = await scan(db, run, args.scope);
  if (args.mode === "dry-run") {
    const manifest = path.join(reportDir, "manifest.jsonl");
    writeJsonl(manifest, result.entries);
    writeReports(reportDir, result.userRows, result.courseRows);
    console.log(JSON.stringify({
      mode: "dry-run",
      project: args.project,
      reportDir: path.relative(repoRoot, reportDir),
      counts: summarize(result.entries),
    }));
    return;
  }

  const hyrox = result.subscriptions.filter((doc) => {
    const data = doc.data();
    return data.family === "HYROX" ||
      (typeof data.planKey === "string" && data.planKey.startsWith("hyrox_"));
  });
  const failures = result.entries.filter((entry) =>
    entry.decision.conversionStatus === "CONVERTIBLE" ||
    entry.decision.conversionStatus === "TARGET_CONFLICT"
  );
  for (const row of result.userRows) {
    row.apply_status = row.conversion_status === "ALREADY_APPLIED"
      ? "VERIFIED"
      : row.conversion_status === "IGNORED" ? "EXCLUDED" : "NEEDS_MIGRATION";
  }
  for (const row of result.courseRows) {
    row.apply_status = row.conversion_status === "ALREADY_APPLIED"
      ? "VERIFIED"
      : row.conversion_status === "IGNORED" ? "EXCLUDED" : "NEEDS_MIGRATION";
  }
  writeReports(reportDir, result.userRows, result.courseRows);
  console.log(JSON.stringify({
    mode: "verify",
    project: args.project,
    failures: failures.length,
    hyroxSubscriptions: hyrox.length,
    hyroxSnapshots: result.hyroxSnapshots,
    reportDir: path.relative(repoRoot, reportDir),
    counts: summarize(result.entries),
  }));
  if (failures.length > 0 || hyrox.length > 0 || result.hyroxSnapshots > 0) {
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(`Migrazione interrotta: ${error.message}`);
  process.exitCode = 1;
});
