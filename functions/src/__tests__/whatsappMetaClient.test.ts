import {
  META_CREDENTIALS_REJECTED_LOG,
  MetaConfig,
  buildMetaTemplateBody,
  metaTransport,
  postToMeta,
} from "../whatsapp/metaClient";
import { TemplateParams } from "../whatsapp/transport";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const TOKEN = "EAAGtokenSuperSegreto123";
const config: MetaConfig = {
  graphVersion: "v26.0",
  phoneNumberId: "106540352242922",
  accessToken: TOKEN,
  templates: { reminder: { name: "promemoria_lezione_prova", lang: "it" } },
};
const PHONE = "+393331234567";
const params: TemplateParams = {
  nome: "Mario Rossi",
  corso: "Corso Excel Avanzato",
  giorno: "15 ottobre 2026",
  orario: "18:00",
};

let fetchMock: jest.Mock;

beforeEach(() => {
  fetchMock = jest.fn();
  (global as Record<string, unknown>).fetch = fetchMock;
});

afterEach(() => jest.clearAllMocks());

function mockJson(status: number, body: unknown) {
  fetchMock.mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(body),
  });
}

const accepted = { messages: [{ id: "wamid.HBgLMzkzMzMxMjM0NTY3FQIAERgS", message_status: "accepted" }] };

function graphError(code: number, extra: Record<string, unknown> = {}) {
  return {
    error: {
      message: "(#131030) Recipient phone number not in allowed list",
      type: "OAuthException",
      code,
      error_subcode: 2494010,
      error_data: { messaging_product: "whatsapp", details: `Recipient ${PHONE.slice(1)} not allowed` },
      fbtrace_id: "AbCdEf123",
      ...extra,
    },
  };
}

function allLoggedText(): string {
  const { logger } = jest.requireMock("firebase-functions");
  return ["info", "warn", "error"]
    .flatMap((level) => (logger[level] as jest.Mock).mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

describe("buildMetaTemplateBody", () => {
  test("template con parametri nominati e destinatario senza +", () => {
    expect(
      buildMetaTemplateBody(PHONE, { name: "promemoria_lezione_prova", lang: "it" }, params)
    ).toEqual({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: "393331234567",
      type: "template",
      template: {
        name: "promemoria_lezione_prova",
        language: { code: "it" },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", parameter_name: "nome", text: "Mario Rossi" },
              { type: "text", parameter_name: "corso", text: "Corso Excel Avanzato" },
              { type: "text", parameter_name: "giorno", text: "15 ottobre 2026" },
              { type: "text", parameter_name: "orario", text: "18:00" },
            ],
          },
        ],
      },
    });
  });
});

describe("postToMeta", () => {
  test("POST sul numero configurato, token solo nell'header", async () => {
    mockJson(200, accepted);
    await postToMeta(config, "reminder", PHONE, params);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://graph.facebook.com/v26.0/106540352242922/messages");
    expect(init.method).toBe("POST");
    expect(init.headers.Authorization).toBe(`Bearer ${TOKEN}`);
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.body).not.toContain(TOKEN);
    expect(JSON.parse(init.body).template.name).toBe("promemoria_lezione_prova");
    expect(init.signal).toBeDefined();
  });

  test("200 → ok con il wamid", async () => {
    mockJson(200, accepted);
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
      ok: true,
      status: 200,
      messageId: "wamid.HBgLMzkzMzMxMjM0NTY3FQIAERgS",
    });
  });

  test("200 senza wamid → ok, ma senza messageId", async () => {
    mockJson(200, {});
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
      ok: true,
      status: 200,
    });
  });

  test("kind senza template → rifiuto locale, nessuna chiamata", async () => {
    await expect(postToMeta(config, "booked", PHONE, params)).resolves.toEqual({
      ok: false,
      status: 0,
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("130429 (rate limit) → transient", async () => {
    mockJson(400, graphError(130429));
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
      ok: false,
      status: 400,
      errorCode: 130429,
      transient: true,
    });
  });

  test.each([100, 131030, 131056, 132000, 132001, 132012, 132015])(
    "code %i → rifiuto non ritentabile",
    async (code) => {
      mockJson(400, graphError(code));
      await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
        ok: false,
        status: 400,
        errorCode: code,
        transient: false,
      });
    }
  );

  test("190 (token scaduto) → log distinto sulle credenziali", async () => {
    mockJson(401, graphError(190));
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toMatchObject({
      ok: false,
      status: 401,
      errorCode: 190,
    });
    const { logger } = jest.requireMock("firebase-functions");
    expect((logger.error as jest.Mock).mock.calls.map((call) => call[0])).toContain(
      META_CREDENTIALS_REJECTED_LOG
    );
  });

  test("5xx con corpo non JSON → ok:false senza errorCode", async () => {
    fetchMock.mockResolvedValue({ ok: false, status: 503, text: async () => "<html>" });
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
      ok: false,
      status: 503,
      transient: false,
    });
  });

  test("errore di rete o timeout → status 0, senza lanciare", async () => {
    fetchMock.mockRejectedValue(new Error("The operation was aborted due to timeout"));
    await expect(postToMeta(config, "reminder", PHONE, params)).resolves.toEqual({
      ok: false,
      status: 0,
    });
  });

  test("il wamid (contiene il numero) non finisce nei log", async () => {
    mockJson(200, accepted);
    await postToMeta(config, "reminder", PHONE, params);
    expect(allLoggedText()).not.toContain(accepted.messages[0].id);
  });

  test("token con newline finale: header pulito", async () => {
    mockJson(200, accepted);
    await postToMeta({ ...config, accessToken: `${TOKEN}\n` }, "reminder", PHONE, params);
    expect(fetchMock.mock.calls[0][1].headers.Authorization).toBe(`Bearer ${TOKEN}`);
  });

  test("nei log code, subcode e fbtrace_id, mai token né numero", async () => {
    mockJson(400, graphError(131030));
    await postToMeta(config, "reminder", PHONE, params);
    fetchMock.mockRejectedValue(new Error(`boom Bearer ${TOKEN} to ${PHONE}`));
    await postToMeta(config, "reminder", PHONE, params);

    const logged = allLoggedText();
    expect(logged).toContain("131030");
    expect(logged).toContain("2494010");
    expect(logged).toContain("AbCdEf123");
    for (const secret of [TOKEN, "3331234567", "Mario Rossi"]) {
      expect(logged).not.toContain(secret);
    }
  });
});

describe("metaTransport", () => {
  test("supporta solo i kind con un template configurato", () => {
    const transport = metaTransport(config);
    expect(transport.name).toBe("meta");
    expect(transport.supports("reminder")).toBe(true);
    expect(transport.supports("booked")).toBe(false);
    expect(
      metaTransport({ ...config, templates: { ...config.templates, booked: { name: "x", lang: "it" } } })
        .supports("booked")
    ).toBe(true);
  });

  test("send delega a postToMeta", async () => {
    mockJson(200, accepted);
    await expect(metaTransport(config).send("reminder", PHONE, params)).resolves.toMatchObject({
      ok: true,
      messageId: accepted.messages[0].id,
    });
  });
});
