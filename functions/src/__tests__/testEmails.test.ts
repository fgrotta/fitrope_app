import { buildTestEnrollmentPayload, sendTestEnrollmentEmailHandler } from "../enrollment/testEmails";

jest.mock("firebase-functions", () => ({ logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() } }));

const base = {
  externalId: "u1", kind: "waitlist" as const, courseName: "Pilates",
  courseDate: "Lunedì 12 ottobre", courseTime: "10:00 - 11:00",
};
const request = (data: unknown = base) => ({ auth: { uid: "admin" }, data });

function deps(users: Record<string, Record<string, unknown>> = {
  admin: { role: "Admin" }, u1: { email: " Mario@Test.it " },
}) {
  const get = jest.fn(async (uid: string) => ({ exists: uid in users, data: () => users[uid] }));
  return {
    db: { collection: () => ({ doc: (uid: string) => ({ get: () => get(uid) }) }) } as never,
    get,
    ensure: jest.fn(async () => ({})),
    post: jest.fn(async (_payload: Record<string, unknown>, _apiKey: string): Promise<Record<string, unknown>> => ({ id: "n1", recipients: 1 })),
  };
}

const env = { ...process.env };
beforeEach(() => { delete process.env.APP_ENV; delete process.env.STAGING_CLONE_MODE; });
afterEach(() => { process.env = { ...env }; });

test("waitlist: template server, oggetto TEST e preheader", () => {
  const p = buildTestEnrollmentPayload({ ...base, spotsAvailable: 2 });
  expect(p).toMatchObject({ target_channel: "email", include_aliases: { external_id: ["u1"] } });
  expect(p.email_subject).toBe('TEST - Posto disponibile nel corso "Pilates"!');
  expect(p.email_body).toContain("2 posti disponibili");
  expect(p.email_preheader).toContain("Pilates");
  expect(p.app_id).toBeDefined();
});

test.each(["trialReminder", "trialConfirmation"] as const)("%s: calendario e sala preservati", (kind) => {
  const p = buildTestEnrollmentPayload({
    ...base, kind, courseId: "c1", startMillis: Date.UTC(2026, 9, 12, 8),
    endMillis: Date.UTC(2026, 9, 12, 9), sala: "Sala 2",
  });
  expect(p.email_subject).toMatch(/^TEST - /);
  expect(p.email_body).toContain("calendar.google.com");
  expect(p.email_body).toContain("courseId=c1");
  expect(p.email_body).toContain("Sala 2");
  expect(p.email_preheader).toContain("Pilates");
});

test.each([null, [], {}, { ...base, kind: "boh" }, { ...base, externalId: "a/b" },
  { ...base, spotsAvailable: -1 }, { ...base, sala: 1 },
  { ...base, kind: "trialReminder", startMillis: 2, endMillis: 1 },
  { ...base, kind: "trialReminder", startMillis: NaN, endMillis: 4 },
])("payload non valido rifiutato prima del trasporto: %j", async (data) => {
  const d = deps();
  await expect(sendTestEnrollmentEmailHandler(request(data), "k", d)).rejects.toMatchObject({ code: "invalid-argument" });
  expect(d.ensure).not.toHaveBeenCalled();
  expect(d.post).not.toHaveBeenCalled();
});

test("senza login nessuna lettura né invio", async () => {
  const d = deps();
  await expect(sendTestEnrollmentEmailHandler({ auth: null, data: base }, "k", d))
    .rejects.toMatchObject({ code: "unauthenticated" });
  expect(d.get).not.toHaveBeenCalled();
  expect(d.post).not.toHaveBeenCalled();
});

test.each(["Trainer", "User", undefined])("ruolo %s non autorizzato", async (role) => {
  const d = deps({ admin: { role } });
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).rejects.toMatchObject({ code: "permission-denied" });
  expect(d.get).toHaveBeenCalledTimes(1);
  expect(d.ensure).not.toHaveBeenCalled();
  expect(d.post).not.toHaveBeenCalled();
});

test("Admin: email normalizzata dal profilo, i selettori del client sono ignorati", async () => {
  const d = deps();
  await expect(sendTestEnrollmentEmailHandler(request({ ...base, email: "evil@x.it", app_id: "evil",
    email_to: ["evil@x.it"], email_body: "evil" }), "k", d)).resolves.toEqual({ id: "n1", recipients: 1 });
  expect(d.ensure).toHaveBeenCalledWith("u1", "mario@test.it", "k");
  expect(d.ensure.mock.invocationCallOrder[0]).toBeLessThan(d.post.mock.invocationCallOrder[0]);
  const p = d.post.mock.calls[0][0];
  expect(p).not.toHaveProperty("email_to");
  expect(p.email_body).not.toBe("evil");
});

test.each([undefined, "", "-", 1])("email mancante/non valida: nessun tentativo via alias (%s)", async (email) => {
  const d = deps({ admin: { role: "Admin" }, u1: { email } });
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).rejects.toMatchObject({ code: "failed-precondition" });
  expect(d.ensure).not.toHaveBeenCalled();
  expect(d.post).not.toHaveBeenCalled();
});

test("profilo destinatario assente", async () => {
  const d = deps({ admin: { role: "Admin" } });
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).rejects.toMatchObject({ code: "not-found" });
  expect(d.post).not.toHaveBeenCalled();
});

test("staging: destinatario fuori allowlist fermato prima dell'ensure", async () => {
  process.env.APP_ENV = "staging";
  process.env.STAGING_CLONE_MODE = "true";
  process.env.STAGING_CLONE_ALLOWED_UIDS = "u1";
  process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST = "qa.develop@example.com";
  const d = deps();
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).resolves.toEqual({ suppressed: true });
  expect(d.ensure).not.toHaveBeenCalled();
  expect(d.post).not.toHaveBeenCalled();
});

test("staging: UID e email entrambi consentiti", async () => {
  process.env.APP_ENV = "staging";
  process.env.STAGING_CLONE_MODE = "true";
  process.env.STAGING_CLONE_ALLOWED_UIDS = "u1";
  process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST = "mario@test.it";
  const d = deps();
  await sendTestEnrollmentEmailHandler(request(), "k", d);
  expect(d.post).toHaveBeenCalledTimes(1);
});

test("ensure soppresso: il post non parte", async () => {
  const d = deps();
  d.ensure.mockResolvedValue({ suppressed: true });
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).resolves.toEqual({ suppressed: true });
  expect(d.post).not.toHaveBeenCalled();
});

test("soppressione del post propagata", async () => {
  const d = deps(); d.post.mockResolvedValue({ suppressed: true });
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).resolves.toEqual({ suppressed: true });
});

test.each([{ id: "" }, { id: "x", recipients: 0 }, { errors: ["No subscribers"] }])("200 senza invio è un errore (%j)", async (response) => {
  const d = deps(); d.post.mockResolvedValue(response);
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).rejects.toMatchObject({ code: "unavailable" });
});

test("errore del provider propagato senza successo apparente", async () => {
  const d = deps(); d.ensure.mockRejectedValue(new Error("provider unavailable"));
  await expect(sendTestEnrollmentEmailHandler(request(), "k", d)).rejects.toThrow("provider unavailable");
  expect(d.post).not.toHaveBeenCalled();
});
