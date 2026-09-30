import { createHash } from "crypto";
import { WhatsappDeps } from "../whatsapp/demoLesson";
import { DemoWebhookKind } from "../whatsapp/payload";
import { DEMO_LOG_COLLECTION } from "../whatsapp/sendLog";
import { sendTestDemoLessonWebhookHandler } from "../whatsapp/testWebhook";
import { SendResult, TemplateParams } from "../whatsapp/transport";
import { makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const NOW = Date.UTC(2026, 9, 14, 17);
const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");
 // domani alle 19:00 → "15 ottobre 2026", "19:00"

function setup(
  env: NodeJS.ProcessEnv = {},
  opts: { name?: "make" | "meta"; result?: SendResult; supports?: (kind: DemoWebhookKind) => boolean } = {}
) {
  const fake = makeWhatsappDb({
    users: { admin: { role: "Admin" }, trainer: { role: "Trainer" }, member: { role: "User" } },
  });
  const post = jest
    .fn<Promise<SendResult>, [DemoWebhookKind, string, TemplateParams]>()
    .mockResolvedValue(opts.result ?? { ok: true, status: 200 });
  const deps: WhatsappDeps = {
    db: fake.db,
    transport: { name: opts.name ?? "make", supports: opts.supports ?? (() => true), send: post },
    nowMillis: NOW,
    env,
  };
  return { deps, post, fake };
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
    expect(post.mock.calls[0]).toEqual([
      "reminder",
      "+393339876543",
      { nome: "Test Test", corso: "Lezione di prova", giorno: "15 ottobre 2026", orario: "19:00" },
    ]);
    expect(res).toEqual({ ok: true, status: 200, transport: "make", payload: expected });
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
    expect(post.mock.calls[0][0]).toBe("booked");
    expect(post.mock.calls[0][2]).toEqual({
      nome: "Mario Rossi",
      corso: "Pole Dance Base",
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
  });

  test("via Meta restituisce trasporto e wamid e registra un documento di prova", async () => {
    const { deps, fake } = setup(
      {},
      { name: "meta", result: { ok: true, status: 200, messageId: "wamid.TEST" } }
    );
    const res = await sendTestDemoLessonWebhookHandler(
      asAdmin({ kind: "reminder", numeroTelefono: "3339876543" }),
      deps
    );
    expect(res).toMatchObject({ ok: true, status: 200, transport: "meta", messageId: "wamid.TEST" });
    const docs = Object.values(fake.store[DEMO_LOG_COLLECTION] ?? {});
    expect(docs).toEqual([
      expect.objectContaining({
        kind: "test",
        testKind: "reminder",
        userId: "admin",
        transport: "meta",
        messageIdHash: sha256("wamid.TEST"),
        outcome: "sent",
        ok: true,
      }),
    ]);
    // Solo identificativi: niente telefono, wamid (lo contiene) né testo del messaggio.
    expect(JSON.stringify(docs)).not.toContain("wamid.TEST");
    expect(JSON.stringify(docs)).not.toContain("3339876543");
    expect(JSON.stringify(docs)).not.toContain("Test Test");
  });

  test("via Meta un rifiuto restituisce l'errorCode senza registrare nulla", async () => {
    const { deps, fake } = setup(
      {},
      { name: "meta", result: { ok: false, status: 400, errorCode: 131030, transient: false } }
    );
    const res = await sendTestDemoLessonWebhookHandler(
      asAdmin({ kind: "reminder", numeroTelefono: "3339876543" }),
      deps
    );
    expect(res).toMatchObject({ ok: false, status: 400, transport: "meta", errorCode: 131030 });
    expect(fake.store[DEMO_LOG_COLLECTION]).toBeUndefined();
  });

  test("kind senza template sul trasporto → failed-precondition, nessun invio", async () => {
    const { deps, post } = setup({}, { name: "meta", supports: (kind) => kind === "reminder" });
    await expect(
      sendTestDemoLessonWebhookHandler(asAdmin({ kind: "booked", numeroTelefono: "3339876543" }), deps)
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(post).not.toHaveBeenCalled();
  });
});
