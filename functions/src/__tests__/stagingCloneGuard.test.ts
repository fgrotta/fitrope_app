import { HttpsError } from "firebase-functions/v2/https";
import { assertStagingCloneAccess, stagingCloneGuarded } from "../stagingCloneGuard";
import { isStagingIdentityAllowed, postToOneSignal } from "../handler";

const previous = {
  mode: process.env.STAGING_CLONE_MODE,
  uids: process.env.STAGING_CLONE_ALLOWED_UIDS,
  appEnv: process.env.APP_ENV,
  emails: process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST,
};

afterEach(() => {
  for (const [key, value] of Object.entries({
    STAGING_CLONE_MODE: previous.mode,
    STAGING_CLONE_ALLOWED_UIDS: previous.uids,
    APP_ENV: previous.appEnv,
    STAGING_NOTIFICATION_EMAIL_ALLOWLIST: previous.emails,
  })) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

test("clone callable gate is fail closed and runs before the handler", () => {
  process.env.STAGING_CLONE_MODE = "true";
  process.env.STAGING_CLONE_ALLOWED_UIDS = "dev_admin,dev_member_open_2x";
  const handler = jest.fn(() => "ok");
  const guarded = stagingCloneGuarded(handler);
  expect(() => guarded({ auth: { uid: "prd_user" } } as never)).toThrow(HttpsError);
  expect(() => guarded({ auth: undefined } as never)).toThrow(HttpsError);
  expect(handler).not.toHaveBeenCalled();
  expect(guarded({ auth: { uid: "dev_admin" } } as never)).toBe("ok");
  process.env.STAGING_CLONE_ALLOWED_UIDS = "";
  expect(() => assertStagingCloneAccess("dev_admin")).toThrow(HttpsError);
});

test("clone notifications permit only QA UID and allowlisted QA email", () => {
  process.env.APP_ENV = "staging";
  process.env.STAGING_CLONE_MODE = "true";
  process.env.STAGING_CLONE_ALLOWED_UIDS = "dev_admin";
  process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST = "admin.develop@example.com";
  expect(isStagingIdentityAllowed("dev_admin", "admin.develop@example.com")).toBe(true);
  expect(isStagingIdentityAllowed("dev_admin", "prd@example.com")).toBe(false);
  expect(isStagingIdentityAllowed("prd_user", "admin.develop@example.com")).toBe(false);
});

test("clone notifications reject additional recipient selectors", async () => {
  process.env.APP_ENV = "staging";
  process.env.STAGING_CLONE_MODE = "true";
  process.env.STAGING_CLONE_ALLOWED_UIDS = "dev_admin";
  const result = await postToOneSignal({
    target_channel: "email",
    include_aliases: { external_id: ["dev_admin"] },
    include_email_tokens: ["someone@example.com"],
  }, "dummy-key");
  expect(result).toEqual({ suppressed: true });
});
