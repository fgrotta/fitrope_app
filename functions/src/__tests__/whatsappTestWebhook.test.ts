import { WhatsappDeps } from "../whatsapp/demoLesson";
import { sendTestDemoLessonWebhookHandler } from "../whatsapp/testWebhook";
import { makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const NOW = Date.UTC(2026, 9, 14, 17); // domani alle 19:00 → "15 ottobre 2026", "19:00"

function setup(env: NodeJS.ProcessEnv = {}) {
  const fake = makeWhatsappDb({
    users: { admin: { role: "Admin" }, trainer: { role: "Trainer" }, member: { role: "User" } },
  });
  const post = jest.fn().mockResolvedValue({ ok: true, status: 200 });
  const deps: WhatsappDeps = {
    db: fake.db,
    webhookUrl: "https://hook.eu1.make.com/abc",
    apiKey: "chiave",
    post,
    nowMillis: NOW,
    env,
  };
  return { deps, post };
}

const asAdmin = (data: unknown) => ({ auth: { uid: "admin" }, data });

afterEach(() => jest.clearAllMocks());

describe("sendTestDemoLessonWebhookHandler", () => {
  test("rifiuta le chiamate non autenticate", async () => {
    const { deps } = setup();
    await expect(
      sendTestDemoLessonWebhookHandler({ data: { numeroTelefono: "3331234567" } }, deps)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test.each([["trainer"], ["member"], ["sconosciuto"]])(
    "nega a %s: servono i permessi Admin",
    async (uid) => {
      const { deps, post } = setup();
      await expect(
        sendTestDemoLessonWebhookHandler(
          { auth: { uid }, data: { numeroTelefono: "3331234567" } },
          deps
        )
      ).rejects.toMatchObject({ code: "permission-denied" });
      expect(post).not.toHaveBeenCalled();
    }
  );

  test("richiede il numero di telefono", async () => {
    const { deps } = setup();
    await expect(sendTestDemoLessonWebhookHandler(asAdmin({}), deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  test("rifiuta un numero non valido spiegando il motivo", async () => {
    const { deps } = setup();
    await expect(
      sendTestDemoLessonWebhookHandler(asAdmin({ numeroTelefono: "n/d" }), deps)
    ).rejects.toThrow(/not_numeric/);
  });

  test("su staging rifiuta i numeri fuori allowlist", async () => {
    const { deps, post } = setup({ APP_ENV: "staging" });
    await expect(
      sendTestDemoLessonWebhookHandler(asAdmin({ numeroTelefono: "3331234567" }), deps)
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(post).not.toHaveBeenCalled();
  });

  test("manda un payload con i default al numero indicato e lo restituisce", async () => {
    const { deps, post } = setup();
    const res = await sendTestDemoLessonWebhookHandler(
      asAdmin({ kind: "reminder", numeroTelefono: "3339876543" }),
      deps
    );
    const expected = {
      tipo: "promemoria",
      nome: "Test Test",
      numero_di_telefono: "+393339876543",
      corso: "Lezione di prova",
      giorno: "15 ottobre 2026",
      orario: "19:00",
    };
    expect(post.mock.calls[0][2]).toEqual(expected);
    expect(res).toEqual({ ok: true, status: 200, payload: expected });
  });

  test("usa nome, corso, giorno e orario passati dal chiamante", async () => {
    const { deps, post } = setup();
    await sendTestDemoLessonWebhookHandler(
      asAdmin({
        numeroTelefono: "3339876543",
        nome: "Mario Rossi",
        corso: "Pole Dance Base",
        giorno: "28 aprile 2026",
        orario: "10:00",
      }),
      deps
    );
    expect(post.mock.calls[0][2]).toMatchObject({
      tipo: "conferma",
      nome: "Mario Rossi",
      corso: "Pole Dance Base",
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
  });
});
