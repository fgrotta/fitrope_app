import { MAKE_AUTH_HEADER, makeTransport } from "../whatsapp/makeClient";
import { TemplateParams, scrubSecrets } from "../whatsapp/transport";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const API_KEY = "chiave-super-segreta";
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

function mockStatus(status: number) {
  fetchMock.mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => "Accepted",
  });
}

describe("scrubSecrets", () => {
  test("sostituisce ogni occorrenza dei secret e ignora quelli vuoti", () => {
    expect(scrubSecrets("a-X-b-X-c-Y", ["X", "", "Y"])).toBe("a-[redacted]-b-[redacted]-c-[redacted]");
  });
});

describe("makeTransport", () => {
  test("supporta entrambi i kind", () => {
    const transport = makeTransport(WEBHOOK_URL, API_KEY);
    expect(transport.name).toBe("make");
    expect(transport.supports("booked")).toBe(true);
    expect(transport.supports("reminder")).toBe(true);
  });

  test("manda il body del contratto Make con la chiave nell'header", async () => {
    mockStatus(200);
    await expect(
      makeTransport(WEBHOOK_URL, API_KEY).send("reminder", "+393331234567", params)
    ).resolves.toEqual({ ok: true, status: 200 });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(WEBHOOK_URL);
    expect(init.headers[MAKE_AUTH_HEADER]).toBe(API_KEY);
    expect(JSON.parse(init.body)).toEqual({
      tipo: "promemoria",
      nome: "Mario Rossi",
      numero_di_telefono: "+393331234567",
      corso: "Corso Excel Avanzato",
      giorno: "15 ottobre 2026",
      orario: "18:00",
    });
  });

  test("HTTP 429 → transient, gli altri errori no", async () => {
    mockStatus(429);
    await expect(
      makeTransport(WEBHOOK_URL, API_KEY).send("booked", "+393331234567", params)
    ).resolves.toEqual({ ok: false, status: 429, transient: true });
    mockStatus(410);
    await expect(
      makeTransport(WEBHOOK_URL, API_KEY).send("booked", "+393331234567", params)
    ).resolves.toEqual({ ok: false, status: 410, transient: false });
  });
});
