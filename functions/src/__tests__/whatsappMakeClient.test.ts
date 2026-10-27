import { postToMake } from "../whatsapp/makeClient";
import { DemoLessonPayload } from "../whatsapp/payload";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const payload: DemoLessonPayload = {
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
  test("POST JSON del payload, senza header di autenticazione", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, payload);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(WEBHOOK_URL);
    expect(init.method).toBe("POST");
    // L'URL è l'unica credenziale: nessuna chiave in header.
    expect(init.headers).toEqual({ "Content-Type": "application/json" });
    expect(init.headers).not.toHaveProperty("Demo-Reminder");
    expect(init.body).toBe(JSON.stringify(payload));
  });

  test("imposta un timeout sulla richiesta", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, payload, { timeoutMs: 500 });
    expect(fetchMock.mock.calls[0][1].signal).toBeDefined();
  });

  test("200 testuale → ok, senza deserializzare il corpo", async () => {
    mockStatus(200);
    await expect(postToMake(WEBHOOK_URL, payload)).resolves.toEqual({
      ok: true,
      status: 200,
    });
  });

  test("risposta di errore → ok:false, senza lanciare", async () => {
    mockStatus(410); // scenario Make disattivato
    await expect(postToMake(WEBHOOK_URL, payload)).resolves.toEqual({
      ok: false,
      status: 410,
    });
  });

  test("errore di rete o timeout → ok:false con status 0, senza lanciare", async () => {
    fetchMock.mockRejectedValue(new Error("The operation was aborted due to timeout"));
    await expect(postToMake(WEBHOOK_URL, payload)).resolves.toEqual({
      ok: false,
      status: 0,
    });
  });

  test("non scrive mai l'URL nei log, ma scrive l'host", async () => {
    mockStatus(500);
    await postToMake(WEBHOOK_URL, payload);
    fetchMock.mockRejectedValue(new Error(`connect ECONNREFUSED ${WEBHOOK_URL}`));
    await postToMake(WEBHOOK_URL, payload);

    const logged = allLoggedText();
    expect(logged).not.toContain(WEBHOOK_URL);
    expect(logged).toContain("hook.eu1.make.com");
  });
});
