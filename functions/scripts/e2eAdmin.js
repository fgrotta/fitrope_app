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
const { Firestore } = require("firebase-admin/firestore");

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

async function main() {
  if (command === "verify-signup") return verifySignup();
  if (command === "delete-signup") return deleteSignup();
  if (command === "cleanup-courses") return cleanupCourses();
  throw new Error(
    "Command must be verify-signup, delete-signup, or cleanup-courses",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("E2E admin command failed:", error);
    process.exit(1);
  });
