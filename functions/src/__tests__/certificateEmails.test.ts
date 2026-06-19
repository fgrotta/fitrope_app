import {
  romeDayWindow,
  selectRecipients,
  buildCertificateEmailPayload,
  mapUserDoc,
  queryUsersInWindow,
  runCertificateEmails,
  sendTestCertificateEmailHandler,
  CandidateUser,
} from "../certificateEmails";
import {
  certificateReminderSubject,
  certificateExpiryTodaySubject,
  certificateReminderBody,
} from "../certificateEmailTemplates";
import {
  ONESIGNAL_APP_ID,
  ONESIGNAL_API_URL,
  ONESIGNAL_USERS_URL,
  HandlerRequest,
} from "../handler";
import { HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

// Silenzia i log durante i test
jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
  },
}));

const API_KEY = "test-api-key";

function user(overrides: Partial<CandidateUser> = {}): CandidateUser {
  return {
    uid: "u1",
    name: "Mario",
    email: "mario@test.it",
    isActive: true,
    emailNotificationsEnabled: true,
    certificatoScadenza: Timestamp.fromMillis(0),
    ...overrides,
  };
}

describe("romeDayWindow", () => {
  test("inverno (CET): contiene un cert a 23:59 ora di Roma del giorno target", () => {
    const now = new Date("2026-01-15T10:00:00Z");
    const w = romeDayWindow(now, 0);
    const cert = Date.parse("2026-01-15T22:59:00Z"); // 23:59 Roma CET
    expect(cert).toBeGreaterThanOrEqual(w.startMs);
    expect(cert).toBeLessThanOrEqual(w.endMs);
    // Giorni adiacenti esclusi
    expect(Date.parse("2026-01-14T22:59:00Z")).toBeLessThan(w.startMs);
    expect(Date.parse("2026-01-16T22:59:00Z")).toBeGreaterThan(w.endMs);
  });

  test("estate (CEST): contiene un cert a 23:59 ora di Roma del giorno target", () => {
    const now = new Date("2026-07-15T10:00:00Z");
    const w = romeDayWindow(now, 0);
    const cert = Date.parse("2026-07-15T21:59:00Z"); // 23:59 Roma CEST
    expect(cert).toBeGreaterThanOrEqual(w.startMs);
    expect(cert).toBeLessThanOrEqual(w.endMs);
    expect(Date.parse("2026-07-14T21:59:00Z")).toBeLessThan(w.startMs);
    expect(Date.parse("2026-07-16T21:59:00Z")).toBeGreaterThan(w.endMs);
  });

  test("dayOffset=10 seleziona il giorno civile a +10", () => {
    const now = new Date("2026-01-15T10:00:00Z");
    const w = romeDayWindow(now, 10);
    const cert = Date.parse("2026-01-25T22:59:00Z");
    expect(cert).toBeGreaterThanOrEqual(w.startMs);
    expect(cert).toBeLessThanOrEqual(w.endMs);
  });

  test("regressione DST: la finestra +10 attraversa il cambio ora (CET→CEST)", () => {
    // now in CET; target day 2026-03-30 è dopo lo spring-forward del 2026-03-29 → CEST
    const now = new Date("2026-03-20T10:00:00Z");
    const w = romeDayWindow(now, 10);
    const cert = Date.parse("2026-03-30T21:59:00Z"); // 23:59 Roma CEST
    expect(cert).toBeGreaterThanOrEqual(w.startMs);
    expect(cert).toBeLessThanOrEqual(w.endMs);
  });
});

describe("selectRecipients", () => {
  test("scarta utenti non attivi", () => {
    expect(selectRecipients([user({ isActive: false })])).toHaveLength(0);
  });

  test("scarta utenti con email disabilitate", () => {
    expect(selectRecipients([user({ emailNotificationsEnabled: false })])).toHaveLength(0);
  });

  test("scarta utenti senza certificato", () => {
    expect(selectRecipients([user({ certificatoScadenza: null })])).toHaveLength(0);
  });

  test("tiene utenti validi", () => {
    expect(selectRecipients([user()])).toHaveLength(1);
  });
});

describe("buildCertificateEmailPayload", () => {
  test("reminder10: canale email, alias e app_id corretti, nessun send_after", () => {
    const p = buildCertificateEmailPayload(user({ uid: "abc" }), "reminder10");
    expect(p.target_channel).toBe("email");
    expect(p.include_aliases).toEqual({ external_id: ["abc"] });
    expect(p.app_id).toBe(ONESIGNAL_APP_ID);
    expect(p.send_after).toBeUndefined();
    expect(p.email_subject).toBe(certificateReminderSubject());
    expect(p.email_body as string).toContain("Mario");
    expect(p.email_body as string).toContain("DNP Sport e Salute");
  });

  test("expiryToday: subject e testo del giorno della scadenza", () => {
    const p = buildCertificateEmailPayload(user(), "expiryToday");
    expect(p.email_subject).toBe(certificateExpiryTodaySubject());
    expect(p.email_body as string).toContain("ultimo giorno");
  });

  test("nome vuoto: saluto 'Ciao 👋' senza doppio spazio", () => {
    const p = buildCertificateEmailPayload(user({ name: "" }), "reminder10");
    expect(p.email_body as string).toContain("Ciao 👋");
    expect(p.email_body as string).not.toContain("Ciao  👋");
  });

  test("subjectPrefix viene anteposto", () => {
    const p = buildCertificateEmailPayload(user(), "reminder10", "TEST - ");
    expect(p.email_subject).toBe(`TEST - ${certificateReminderSubject()}`);
  });
});

describe("mapUserDoc", () => {
  test("applica i default (isActive/email true, uid da doc.id, email null)", () => {
    const u = mapUserDoc({ id: "doc-1", data: () => ({ name: "Lucia" }) });
    expect(u).toEqual({
      uid: "doc-1",
      name: "Lucia",
      email: null,
      isActive: true,
      emailNotificationsEnabled: true,
      certificatoScadenza: null,
    });
  });

  test("legge l'email dal documento", () => {
    const u = mapUserDoc({ id: "doc-2", data: () => ({ name: "Tom", email: "tom@x.it" }) });
    expect(u.email).toBe("tom@x.it");
  });
});

describe("queryUsersInWindow", () => {
  test("interroga la collection users filtrando solo su certificatoScadenza", async () => {
    const whereCalls: Array<{ field: string; op: string }> = [];
    let collectionName = "";
    const query: Record<string, unknown> = {
      where: (field: string, op: string) => {
        whereCalls.push({ field, op });
        return query;
      },
      get: async () => ({
        docs: [{ id: "u9", data: () => ({ uid: "u9", name: "Test" }) }],
      }),
    };
    const fakeDb = {
      collection: (name: string) => {
        collectionName = name;
        return query;
      },
    };

    const res = await queryUsersInWindow(
      fakeDb as never,
      { startMs: 0, endMs: 1000 }
    );

    expect(collectionName).toBe("users");
    expect(whereCalls.every((c) => c.field === "certificatoScadenza")).toBe(true);
    expect(res).toHaveLength(1);
    expect(res[0].uid).toBe("u9");
  });
});

describe("runCertificateEmails", () => {
  function fakeDbReturning(resultsQueue: Array<Array<{ id: string; data: () => Record<string, unknown> }>>) {
    const query: Record<string, unknown> = {
      where: () => query,
      get: async () => ({ docs: resultsQueue.shift() ?? [] }),
    };
    return { collection: () => query } as never;
  }

  const cert = () => Timestamp.fromMillis(1_900_000_000_000);
  const now = new Date("2026-01-15T10:00:00Z");

  test("invia un'email per destinatario e ritorna i contatori", async () => {
    const db = fakeDbReturning([
      // prima query (dayOffset 10): promemoria
      [{ id: "r1", data: () => ({ uid: "r1", name: "A", email: "a@x.it", certificatoScadenza: cert() }) }],
      // seconda query (dayOffset 0): scadenza oggi
      [
        { id: "e1", data: () => ({ uid: "e1", name: "B", email: "b@x.it", certificatoScadenza: cert() }) },
        { id: "e2", data: () => ({ uid: "e2", name: "C", email: "c@x.it", certificatoScadenza: cert() }) },
      ],
    ]);
    const post = jest.fn().mockResolvedValue({ id: "x" });
    const ensure = jest.fn().mockResolvedValue({});

    const res = await runCertificateEmails({ db, apiKey: API_KEY, post, ensure, now });

    expect(res).toEqual({ reminderSent: 1, expirySent: 2 });
    expect(post).toHaveBeenCalledTimes(3);
    const subjects = post.mock.calls.map((c) => (c[0] as Record<string, unknown>).email_subject);
    expect(subjects.filter((s) => s === certificateReminderSubject())).toHaveLength(1);
    expect(subjects.filter((s) => s === certificateExpiryTodaySubject())).toHaveLength(2);
  });

  test("assicura la subscription OneSignal PRIMA di inviare (utente mai loggato)", async () => {
    const order: string[] = [];
    const db = fakeDbReturning([
      [{ id: "r1", data: () => ({ uid: "r1", name: "A", email: "a@x.it", certificatoScadenza: cert() }) }],
      [],
    ]);
    const ensure = jest.fn().mockImplementation(async () => {
      order.push("ensure");
    });
    const post = jest.fn().mockImplementation(async () => {
      order.push("post");
      return { id: "x" };
    });

    await runCertificateEmails({ db, apiKey: API_KEY, post, ensure, now });

    expect(ensure).toHaveBeenCalledWith("r1", "a@x.it", API_KEY);
    expect(order).toEqual(["ensure", "post"]);
  });

  test("senza email non chiama ensure ma tenta comunque l'invio via external_id", async () => {
    const db = fakeDbReturning([
      [{ id: "r1", data: () => ({ uid: "r1", name: "A", certificatoScadenza: cert() }) }], // niente email
      [],
    ]);
    const ensure = jest.fn().mockResolvedValue({});
    const post = jest.fn().mockResolvedValue({ id: "x" });

    const res = await runCertificateEmails({ db, apiKey: API_KEY, post, ensure, now });

    expect(ensure).not.toHaveBeenCalled();
    expect(post).toHaveBeenCalledTimes(1);
    expect(res.reminderSent).toBe(1);
  });

  test("un ensure fallito salta l'utente senza interrompere il run", async () => {
    const db = fakeDbReturning([
      [
        { id: "r1", data: () => ({ uid: "r1", name: "A", email: "a@x.it", certificatoScadenza: cert() }) },
        { id: "r2", data: () => ({ uid: "r2", name: "B", email: "b@x.it", certificatoScadenza: cert() }) },
      ],
      [],
    ]);
    const ensure = jest
      .fn()
      .mockRejectedValueOnce(new Error("ensure down"))
      .mockResolvedValueOnce({});
    const post = jest.fn().mockResolvedValue({ id: "x" });

    const res = await runCertificateEmails({ db, apiKey: API_KEY, post, ensure, now });

    expect(res).toEqual({ reminderSent: 1, expirySent: 0 });
    expect(post).toHaveBeenCalledTimes(1); // solo il secondo utente
  });

  test("un invio fallito non interrompe il run", async () => {
    const db = fakeDbReturning([
      [
        { id: "r1", data: () => ({ uid: "r1", name: "A", email: "a@x.it", certificatoScadenza: cert() }) },
        { id: "r2", data: () => ({ uid: "r2", name: "B", email: "b@x.it", certificatoScadenza: cert() }) },
      ],
      [],
    ]);
    const ensure = jest.fn().mockResolvedValue({});
    const post = jest
      .fn()
      .mockRejectedValueOnce(new Error("OneSignal down"))
      .mockResolvedValueOnce({ id: "ok" });

    const res = await runCertificateEmails({ db, apiKey: API_KEY, post, ensure, now });

    expect(res).toEqual({ reminderSent: 1, expirySent: 0 });
    expect(post).toHaveBeenCalledTimes(2);
  });
});

describe("sendTestCertificateEmailHandler", () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ id: "notif-1" }),
    } as Response);
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => jest.clearAllMocks());

  test("rifiuta richieste non autenticate", async () => {
    const req: HandlerRequest = { auth: null, data: { externalId: "u1" } };
    await expect(sendTestCertificateEmailHandler(req, API_KEY)).rejects.toMatchObject({
      code: "unauthenticated",
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("rifiuta payload senza externalId", async () => {
    const req: HandlerRequest = { auth: { uid: "admin" }, data: {} };
    await expect(sendTestCertificateEmailHandler(req, API_KEY)).rejects.toThrow(HttpsError);
  });

  test("invia con prefisso TEST e variante scelta", async () => {
    const req: HandlerRequest = {
      auth: { uid: "admin" },
      data: { externalId: "u1", firstName: "Giulia", kind: "expiryToday" },
    };
    const res = await sendTestCertificateEmailHandler(req, API_KEY);
    expect(res).toEqual({ id: "notif-1" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body.email_subject).toBe(`TEST - ${certificateExpiryTodaySubject()}`);
    expect(body.include_aliases).toEqual({ external_id: ["u1"] });
    expect(body.email_body).toContain("Giulia");
  });

  test("con email: assicura la subscription PRIMA dell'invio", async () => {
    const req: HandlerRequest = {
      auth: { uid: "admin" },
      data: { externalId: "u1", firstName: "Giulia", email: "g@x.it", kind: "reminder10" },
    };
    await sendTestCertificateEmailHandler(req, API_KEY);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toBe(ONESIGNAL_USERS_URL); // ensure user
    expect(fetchMock.mock.calls[1][0]).toBe(ONESIGNAL_API_URL); // invio notifica
  });
});

describe("template drift guard", () => {
  test("subject e footer corrispondono al branding atteso", () => {
    expect(certificateReminderSubject()).toBe("Il tuo certificato medico sta per scadere");
    expect(certificateExpiryTodaySubject()).toBe("Il tuo certificato medico scade oggi");
    expect(certificateReminderBody("Mario")).toContain("— Il team Fit House");
  });
});
