import { execFileSync } from "child_process";
import { readFileSync } from "fs";
import * as path from "path";
import {
  initializeTestEnvironment, assertFails, assertSucceeds, RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

let env: RulesTestEnvironment;
const root = path.join(__dirname, "../../..");

beforeAll(async () => {
  execFileSync("python3", [path.join(root, "scripts/generate_staging_clone_rules.py")]);
  env = await initializeTestEnvironment({
    projectId: "demo-staging-clone-rules",
    firestore: { rules: readFileSync(path.join(root, ".context/staging-clone.rules"), "utf8") },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("users/dev_admin").set({ uid: "dev_admin", role: "Admin" });
    await db.doc("users/prd_member").set({ uid: "prd_member", role: "User" });
    await db.doc("courses/course1").set({ name: "Corso" });
  });
});

afterAll(async () => { await env.cleanup(); });

test("QA admin reads clone; any other signed-in UID is denied", async () => {
  const qa = env.authenticatedContext("dev_admin").firestore();
  const outsider = env.authenticatedContext("prd_member").firestore();
  await assertSucceeds(qa.doc("users/prd_member").get());
  await assertSucceeds(qa.doc("courses/course1").get());
  await assertFails(outsider.doc("users/prd_member").get());
  await assertFails(outsider.doc("courses/course1").get());
  await assertFails(outsider.doc("users/prd_member").update({ name: "x" }));
});
