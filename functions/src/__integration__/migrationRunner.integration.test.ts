import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
} from "fs";
import * as path from "path";
import { execFileSync } from "child_process";

const PROJECT_ID = "demo-fitrope-migration";
const app = admin.apps.find((candidate) => candidate?.name === "migration-runner") ??
  admin.initializeApp({ projectId: PROJECT_ID }, "migration-runner");
const db = app.firestore();
const repoRoot = path.resolve(__dirname, "../../..");
const runner = path.join(repoRoot, "scripts", "backfillCourseModel.js");
const reportRoot = path.join(repoRoot, ".context", "migrations");
const testRoot = path.join(reportRoot, `jest-${process.pid}-${Date.now()}`);
let lastRunnerOutput = "";

function run(args: string[]): Record<string, unknown> {
  const stdout = execFileSync(
    process.execPath,
    [runner, `--project=${PROJECT_ID}`, ...args],
    {
      cwd: repoRoot,
      env: process.env,
      encoding: "utf8",
    }
  ).trim();
  lastRunnerOutput = stdout;
  return JSON.parse(stdout.split(/\r?\n/).at(-1) ?? "{}");
}

function reportArg(name: string): string {
  return `--report-dir=.context/migrations/${path.basename(testRoot)}/${name}`;
}

beforeAll(async () => {
  mkdirSync(testRoot, { recursive: true, mode: 0o700 });
  await db.recursiveDelete(db.collection("courses"));
  await db.recursiveDelete(db.collection("users"));
  await db.recursiveDelete(db.collection("subscriptions"));
});

afterAll(async () => {
  await app.delete();
  rmSync(testRoot, { recursive: true, force: true });
});

describe("runner migrazione contro Firestore Emulator", () => {
  test("dry-run non scrive; apply e atomica e la seconda apply non scrive", async () => {
    const end = Timestamp.fromDate(new Date("2026-09-20T16:00:00.000Z"));
    await db.collection("courses").doc("legacy-course").set({
      uid: "legacy-course",
      tags: ["Open"],
    });
    await db.collection("users").doc("legacy-user").set({
      uid: "legacy-user",
      email: "persona-riservata@example.com",
      role: "User",
      tipologiaCorsoTags: ["Open"],
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 2,
      fineIscrizione: end,
    });

    run(["--dry-run", "--scope=all", reportArg("dry")]);
    expect(lastRunnerOutput).not.toContain("persona-riservata@example.com");
    const courseAfterDryRun = await db.collection("courses").doc("legacy-course").get();
    expect(courseAfterDryRun.get("courseModelV2")).toBeUndefined();
    expect((await db.collection("subscriptions").get()).empty).toBe(true);

    const manifest = path.join(testRoot, "dry", "manifest.jsonl");
    expect(statSync(manifest).mode & 0o777).toBe(0o600);
    const manifestArg = `--manifest=.context/migrations/${path.basename(testRoot)}/dry/manifest.jsonl`;
    const first = run([
      "--apply",
      "--scope=all",
      manifestArg,
      `--confirm-project=${PROJECT_ID}`,
      reportArg("apply-1"),
    ]);
    expect(first.counts).toEqual({ APPLIED: 2 });

    const migratedCourse = await db.collection("courses").doc("legacy-course").get();
    expect(migratedCourse.data()).toMatchObject({
      courseType: "open",
      tag: null,
      courseModelV2: true,
      tags: ["Open"],
    });
    const subscription = await db.collection("subscriptions").doc("legacy_open_legacy-user").get();
    const migratedUser = await db.collection("users").doc("legacy-user").get();
    expect(subscription.exists).toBe(true);
    expect(migratedUser.get("activeSubscriptions")).toHaveLength(1);
    expect(migratedUser.get("legacySubscriptionMigration")).toMatchObject({
      source: "BATCH",
      subscriptionId: "legacy_open_legacy-user",
      planKey: "open_2x_1m",
    });
    expect(
      readFileSync(
        path.join(testRoot, "apply-1", "enrollment-integrity-report.csv"),
        "utf8"
      )
    ).toContain("severity");
    const courseUpdateTime = migratedCourse.updateTime!.toMillis();
    const userUpdateTime = migratedUser.updateTime!.toMillis();

    const second = run([
      "--apply",
      "--scope=all",
      manifestArg,
      `--confirm-project=${PROJECT_ID}`,
      reportArg("apply-2"),
    ]);
    expect(second.counts).toEqual({ ALREADY_APPLIED: 2 });
    expect(
      (await db.collection("courses").doc("legacy-course").get()).updateTime!.toMillis()
    ).toBe(courseUpdateTime);
    expect(
      (await db.collection("users").doc("legacy-user").get()).updateTime!.toMillis()
    ).toBe(userUpdateTime);

    const verified = run(["--verify", "--scope=all", reportArg("verify")]);
    expect(verified.failures).toBe(0);
    expect(verified.hyroxSubscriptions).toBe(0);
    expect(verified.hyroxSnapshots).toBe(0);
  });

  test("SOURCE_DRIFT e TARGET_CONFLICT non sovrascrivono dati correnti", async () => {
    await db.collection("courses").doc("drift-course").set({
      uid: "drift-course",
      tags: ["Open"],
    });
    run(["--dry-run", "--scope=courses", reportArg("drift-dry")]);
    await db.collection("courses").doc("drift-course").update({
      tags: ["Personal Trainer"],
    });
    const drift = run([
      "--apply",
      "--scope=courses",
      `--manifest=.context/migrations/${path.basename(testRoot)}/drift-dry/manifest.jsonl`,
      `--confirm-project=${PROJECT_ID}`,
      reportArg("drift-apply"),
    ]);
    expect((drift.counts as Record<string, number>).SOURCE_DRIFT).toBe(1);
    expect((await db.collection("courses").doc("drift-course").get()).data()).toMatchObject({
      tags: ["Personal Trainer"],
    });

    const end = Timestamp.fromDate(new Date("2026-09-20T16:00:00.000Z"));
    await db.collection("users").doc("conflict-user").set({
      uid: "conflict-user",
      role: "User",
      tipologiaCorsoTags: ["Open"],
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 2,
      fineIscrizione: end,
    });
    run(["--dry-run", "--scope=users", reportArg("conflict-dry")]);
    await db.collection("subscriptions").doc("legacy_open_conflict-user").set({
      userId: "conflict-user",
      family: "OPEN",
      planKey: "open_3x_1m",
    });
    const conflict = run([
      "--apply",
      "--scope=users",
      `--manifest=.context/migrations/${path.basename(testRoot)}/conflict-dry/manifest.jsonl`,
      `--confirm-project=${PROJECT_ID}`,
      reportArg("conflict-apply"),
    ]);
    expect((conflict.counts as Record<string, number>).TARGET_CONFLICT).toBe(1);
    expect((await db.collection("users").doc("conflict-user").get()).get("activeSubscriptions"))
      .toBeUndefined();

    const csv = readFileSync(
      path.join(testRoot, "conflict-apply", "users-migration-report.csv"),
      "utf8"
    );
    expect(csv).toContain("TARGET_CONFLICT");
  });

  test("audit iscrizioni classifica le incoerenze future come blocker", async () => {
    const future = Timestamp.fromMillis(Date.now() + 7 * 86400 * 1000);
    await db.collection("courses").doc("audit-future").set({
      uid: "audit-future",
      tags: ["Open"],
      startDate: future,
      subscribed: 1,
      waitlist: [],
    });
    await db.collection("users").doc("audit-user").set({
      uid: "audit-user",
      role: "User",
      waitlistCourses: ["audit-future"],
    });
    run(["--dry-run", "--scope=all", reportArg("audit")]);
    const csv = readFileSync(
      path.join(testRoot, "audit", "enrollment-integrity-report.csv"),
      "utf8"
    );
    expect(csv).toContain("BLOCKER;WAITLIST_NOT_RECIPROCAL_USER");
    expect(csv).toContain("BLOCKER;SUBSCRIBED_COUNT_MISMATCH");
  });

  test("un marker ADMIN_GUIDED rende il successivo batch idempotente", async () => {
    const userId = "guided-before-batch";
    await db.collection("users").doc(userId).set({
      uid: userId,
      role: "User",
      tipologiaCorsoTags: ["Open"],
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 2,
      fineIscrizione: Timestamp.fromMillis(Date.now() + 15 * 86400 * 1000),
    });
    run(["--dry-run", "--scope=users", reportArg("guided-dry")]);
    await db.collection("subscriptions").doc("legacy_guided_guided-before-batch").set({
      userId,
      family: "PT",
      planKey: "pt_10i_1m",
    });
    await db.collection("users").doc(userId).update({
      legacySubscriptionMigration: {
        version: 1,
        source: "ADMIN_GUIDED",
        subscriptionId: "legacy_guided_guided-before-batch",
      },
    });

    const applied = run([
      "--apply",
      "--scope=users",
      `--manifest=.context/migrations/${path.basename(testRoot)}/guided-dry/manifest.jsonl`,
      `--confirm-project=${PROJECT_ID}`,
      reportArg("guided-apply"),
    ]);
    expect((applied.counts as Record<string, number>).ALREADY_APPLIED).toBeGreaterThan(0);
    expect((await db.collection("subscriptions").doc(`legacy_open_${userId}`).get()).exists)
      .toBe(false);
  });
});
