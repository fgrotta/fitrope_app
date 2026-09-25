import { MAKE_AUTH_HEADER, postToMake } from "../whatsapp/makeClient";
import { DemoLessonPayload } from "../whatsapp/payload";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const API_KEY = "chiave-super-segreta";
const payload: DemoLessonPayload = {
  tipo: "promemoria",
  nome: "Mario Rossi",
  numero_di_telefono: "+393331234567",
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

/** Make risponde con il testo "Accepted", non con JSON. */
function mockStatus(status: number) {
  fetchMock.mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => "Accepted",
  });
}

function allLoggedText(): string {
  const { logger } = jest.requireMock("firebase-functions");
  return ["info", "warn", "error"]
    .flatMap((level) => (logger[level] as jest.Mock).mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

describe("postToMake", () => {
  test("manda la chiave nell'header Demo-Reminder e non nel body", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, API_KEY, payload);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(WEBHOOK_URL);
    expect(init.method).toBe("POST");
    expect(init.headers[MAKE_AUTH_HEADER]).toBe(API_KEY);
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.body).toBe(JSON.stringify(payload));
    expect(init.body).not.toContain(API_KEY);
  });

  test("imposta un timeout sulla richiesta", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, API_KEY, payload, { timeoutMs: 500 });
    expect(fetchMock.mock.calls[0][1].signal).toBeDefined();
  });

  test("200 testuale → ok, senza deserializzare il corpo", async () => {
    mockStatus(200);
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: true,
      status: 200,
    });
  });

  test("risposta di errore → ok:false, senza lanciare", async () => {
    mockStatus(410); // scenario Make disattivato
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: false,
      status: 410,
    });
  });

  test("errore di rete o timeout → ok:false con status 0, senza lanciare", async () => {
    fetchMock.mockRejectedValue(new Error("The operation was aborted due to timeout"));
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: false,
      status: 0,
    });
  });

  test("non scrive mai URL né chiave nei log, ma scrive l'host", async () => {
    mockStatus(500);
    await postToMake(WEBHOOK_URL, API_KEY, payload);
    fetchMock.mockRejectedValue(new Error(`connect ECONNREFUSED ${WEBHOOK_URL} key=${API_KEY}`));
    await postToMake(WEBHOOK_URL, API_KEY, payload);

    const logged = allLoggedText();
    expect(logged).not.toContain(WEBHOOK_URL);
    expect(logged).not.toContain(API_KEY);
    expect(logged).toContain("hook.eu1.make.com");
  });
});
