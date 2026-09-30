import { createHmac } from "crypto";
import { DEMO_LOG_COLLECTION } from "../whatsapp/sendLog";
import {
  SIGNATURE_HEADER,
  StatusWebhookRequest,
  handleStatusWebhook,
  verifySignature,
} from "../whatsapp/statusWebhook";
import { Store, WhatsappFakeDbOptions, makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const APP_SECRET = "app-secret-di-test";
const VERIFY_TOKEN = "verify-token-casuale";
const PHONE_DIGITS = "393331234567";

const sign = (raw: string, secret = APP_SECRET) =>
  `sha256=${createHmac("sha256", secret).update(raw).digest("hex")}`;

function status(id: string, value: string, timestamp: number, extra: Record<string, unknown> = {}) {
  return { id, status: value, timestamp: String(timestamp), recipient_id: PHONE_DIGITS, ...extra };
}

function payload(value: Record<string, unknown>, field = "messages") {
  return {
    object: "whatsapp_business_account",
    entry: [
      {
        id: "WABA_ID",
        changes: [
          {
            field,
            value: { messaging_product: "whatsapp", metadata: { phone_number_id: "1065" }, ...value },
          },
        ],
      },
    ],
  };
}

function post(body: unknown, signature?: string | null): StatusWebhookRequest {
  const raw = JSON.stringify(body);
  return {
    method: "POST",
    query: {},
    headers: signature === null ? {} : { [SIGNATURE_HEADER]: signature ?? sign(raw) },
    rawBody: Buffer.from(raw),
  };
}

function setup(store?: Store, opts?: WhatsappFakeDbOptions) {
  const fake = makeWhatsappDb(
    store ?? {
      [DEMO_LOG_COLLECTION]: {
        reminder_u1_c1: { kind: "reminder", ok: true, outcome: "sent", messageId: "wamid.A" },
      },
    },
    opts
  );
  const deps = { db: fake.db, appSecret: APP_SECRET, verifyToken: VERIFY_TOKEN };
  const doc = () => fake.store[DEMO_LOG_COLLECTION]?.reminder_u1_c1;
  return { fake, deps, doc };
}

function allLoggedText(): string {
  const { logger } = jest.requireMock("firebase-functions");
  return ["info", "warn", "error"]
    .flatMap((level) => (logger[level] as jest.Mock).mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

afterEach(() => jest.clearAllMocks());

describe("verifySignature", () => {
  const raw = Buffer.from('{"a":1}');

  test("accetta la firma HMAC-SHA256 del corpo grezzo", () => {
    expect(verifySignature(raw, sign('{"a":1}'), APP_SECRET)).toBe(true);
  });

  test.each([
    ["assente", undefined],
    ["vuota", ""],
    ["senza prefisso", sign('{"a":1}').slice("sha256=".length)],
    ["con un altro secret", sign('{"a":1}', "altro")],
    ["di un altro corpo", sign('{"a":2}')],
    ["troncata", sign('{"a":1}').slice(0, 20)],
  ])("rifiuta una firma %s", (_label, header) => {
    expect(verifySignature(raw, header, APP_SECRET)).toBe(false);
  });

  test("rifiuta se manca il corpo grezzo", () => {
    expect(verifySignature(undefined, sign('{"a":1}'), APP_SECRET)).toBe(false);
  });
});

describe("handleStatusWebhook — verifica GET", () => {
  const get = (query: Record<string, unknown>): StatusWebhookRequest => ({
    method: "GET",
    query,
    headers: {},
  });

  test("risponde hub.challenge in chiaro con il verify token giusto", async () => {
    const { deps } = setup();
    await expect(
      handleStatusWebhook(
        get({ "hub.mode": "subscribe", "hub.verify_token": VERIFY_TOKEN, "hub.challenge": "1158201444" }),
        deps
      )
    ).resolves.toEqual({ status: 200, body: "1158201444" });
  });

  test.each([
    ["token sbagliato", { "hub.mode": "subscribe", "hub.verify_token": "no", "hub.challenge": "1" }],
    ["mode diverso", { "hub.mode": "unsubscribe", "hub.verify_token": VERIFY_TOKEN, "hub.challenge": "1" }],
    ["token assente", { "hub.mode": "subscribe", "hub.challenge": "1" }],
  ])("403 con %s", async (_label, query) => {
    const { deps } = setup();
    await expect(handleStatusWebhook(get(query), deps)).resolves.toMatchObject({ status: 403 });
  });
});

describe("handleStatusWebhook — POST", () => {
  test("405 su altri metodi", async () => {
    const { deps } = setup();
    await expect(
      handleStatusWebhook({ method: "PUT", query: {}, headers: {} }, deps)
    ).resolves.toMatchObject({ status: 405 });
  });

  test("401 senza firma o con firma sbagliata, senza toccare Firestore", async () => {
    const { deps, fake } = setup();
    const body = payload({ statuses: [status("wamid.A", "delivered", 1_760_000_000)] });
    await expect(handleStatusWebhook(post(body, null), deps)).resolves.toMatchObject({ status: 401 });
    await expect(handleStatusWebhook(post(body, sign("altro")), deps)).resolves.toMatchObject({
      status: 401,
    });
    expect(fake.ops).toEqual([]);
  });

  test("applica gli stati al documento del wamid", async () => {
    const { deps, doc } = setup();
    const res = await handleStatusWebhook(
      post(payload({ statuses: [status("wamid.A", "delivered", 1_760_000_000)] })),
      deps
    );
    expect(res).toEqual({ status: 200, body: "EVENT_RECEIVED" });
    expect(doc()).toMatchObject({ deliveryStatus: "delivered", outcome: "sent" });
  });

  test("stati fuori ordine e duplicati nello stesso callback: vince il rango più alto", async () => {
    const { deps, doc } = setup();
    await handleStatusWebhook(
      post(
        payload({
          statuses: [
            status("wamid.A", "read", 1_760_000_020),
            status("wamid.A", "sent", 1_760_000_000),
            status("wamid.A", "delivered", 1_760_000_010),
            status("wamid.A", "read", 1_760_000_020),
          ],
        })
      ),
      deps
    );
    expect(doc()).toMatchObject({ deliveryStatus: "read" });
  });

  test("failed registra l'errore di consegna", async () => {
    const { deps, doc } = setup();
    await handleStatusWebhook(
      post(
        payload({
          statuses: [
            status("wamid.A", "failed", 1_760_000_000, {
              errors: [
                {
                  code: 131026,
                  title: "Message undeliverable",
                  error_data: { details: `Numero ${PHONE_DIGITS} non su WhatsApp` },
                },
              ],
            }),
          ],
        })
      ),
      deps
    );
    expect(doc()).toMatchObject({
      deliveryStatus: "failed",
      deliveryError: { code: 131026, title: "Message undeliverable" },
    });
  });

  test("messaggi in ingresso: 200 e ignorati, senza salvarne il contenuto", async () => {
    const { deps, fake } = setup();
    const res = await handleStatusWebhook(
      post(
        payload({
          contacts: [{ wa_id: PHONE_DIGITS, profile: { name: "Mario Rossi" } }],
          messages: [{ from: PHONE_DIGITS, id: "wamid.IN", type: "text", text: { body: "STOP" } }],
        })
      ),
      deps
    );
    expect(res.status).toBe(200);
    expect(fake.ops.some((op) => op.startsWith("update"))).toBe(false);
    expect(allLoggedText()).not.toContain("STOP");
  });

  test("wamid sconosciuto e campi diversi da messages: 200 senza scritture", async () => {
    const { deps, fake } = setup();
    await expect(
      handleStatusWebhook(post(payload({ statuses: [status("wamid.Z", "delivered", 1)] })), deps)
    ).resolves.toMatchObject({ status: 200 });
    await expect(
      handleStatusWebhook(post(payload({ event: "APPROVED" }, "message_template_status_update")), deps)
    ).resolves.toMatchObject({ status: 200 });
    expect(fake.ops.some((op) => op.startsWith("update"))).toBe(false);
  });

  test("corpo firmato ma non JSON: 200", async () => {
    const { deps } = setup();
    const raw = "non json";
    await expect(
      handleStatusWebhook(
        { method: "POST", query: {}, headers: { [SIGNATURE_HEADER]: sign(raw) }, rawBody: Buffer.from(raw) },
        deps
      )
    ).resolves.toMatchObject({ status: 200 });
  });

  test("Firestore in errore: 200 lo stesso (un 5xx farebbe ritentare Meta per giorni)", async () => {
    const { deps } = setup(undefined, { updateError: () => new Error("14 UNAVAILABLE") });
    await expect(
      handleStatusWebhook(post(payload({ statuses: [status("wamid.A", "delivered", 1)] })), deps)
    ).resolves.toMatchObject({ status: 200 });
    const { logger } = jest.requireMock("firebase-functions");
    expect(logger.error).toHaveBeenCalled();
  });

  test("non logga mai recipient_id né secret", async () => {
    const { deps } = setup();
    await handleStatusWebhook(
      post(
        payload({
          statuses: [
            status("wamid.A", "sent", 1, { pricing: { billable: true, category: "utility" } }),
            status("wamid.Z", "delivered", 2),
          ],
        })
      ),
      deps
    );
    await handleStatusWebhook(post(payload({ statuses: [] }), sign("x")), deps);
    const logged = allLoggedText();
    expect(logged).toContain("utility");
    for (const secret of [PHONE_DIGITS, "3331234567", APP_SECRET, VERIFY_TOKEN]) {
      expect(logged).not.toContain(secret);
    }
  });
});
