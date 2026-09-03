import {
  DEMO_LOG_COLLECTION,
  MAKE_AUTH_HEADER,
  TIPO_BY_KIND,
  buildDemoLessonPayload,
  buildNome,
  claimSend,
  confirmSend,
  demoLogDocId,
  normalizePhoneE164,
  postToMake,
  releaseSend,
  sanitizeTemplateParam,
  wasNotifiedToday,
  checkRecipient,
  mapDemoCourseDoc,
  mapDemoUserDoc,
  notifyDemoLessonBookedHandler,
  runDemoLessonReminders,
  sendTestDemoLessonWebhookHandler,
} from "../makeWebhook";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";

// Silenzia i log durante i test
jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
  },
}));

describe("normalizePhoneE164", () => {
  it.each([
    ["null", null],
    ["undefined", undefined],
    ["stringa vuota", ""],
    ["soli spazi", "   "],
  ])("scarta %s con reason empty", (_label, input) => {
    expect(normalizePhoneE164(input as string | null)).toMatchObject({
      e164: null,
      reason: "empty",
    });
  });

  it("riconosce il placeholder '-'", () => {
    expect(normalizePhoneE164("-")).toMatchObject({ e164: null, reason: "placeholder" });
  });

  it("scarta il testo non numerico", () => {
    expect(normalizePhoneE164("n/d")).toMatchObject({ e164: null, reason: "not_numeric" });
    expect(normalizePhoneE164("no cell")).toMatchObject({ e164: null, reason: "not_numeric" });
  });

  it.each([
    ["spazi", "333 123 4567"],
    ["trattini e punti", "333-123.4567"],
    ["parentesi", "(333) 1234567"],
    ["NBSP", "333 1234567"],
  ])("rimuove i separatori (%s)", (_label, input) => {
    expect(normalizePhoneE164(input)).toMatchObject({
      e164: "+393331234567",
      digits: "393331234567",
      likelyMobile: true,
    });
  });

  it("normalizza il caso nominale a 10 cifre", () => {
    expect(normalizePhoneE164("3331234567")).toEqual({
      e164: "+393331234567",
      digits: "393331234567",
      likelyMobile: true,
    });
  });

  it("accetta un mobile a 9 cifre", () => {
    expect(normalizePhoneE164("335123456")).toMatchObject({
      e164: "+39335123456",
      likelyMobile: true,
    });
  });

  it("lascia invariato un numero già internazionale", () => {
    expect(normalizePhoneE164("+393331234567")).toMatchObject({
      e164: "+393331234567",
      likelyMobile: true,
    });
  });

  it("converte il prefisso 00 in +", () => {
    expect(normalizePhoneE164("00393331234567")).toMatchObject({
      e164: "+393331234567",
      likelyMobile: true,
    });
  });

  it("NON tratta un 39 iniziale su 10 cifre come prefisso paese", () => {
    // 3931234567 è un mobile che inizia per 39, non +39 seguito da 31234567.
    expect(normalizePhoneE164("3931234567")).toMatchObject({
      e164: "+393931234567",
      likelyMobile: true,
    });
  });

  it("preserva un numero estero senza forzare il +39", () => {
    expect(normalizePhoneE164("+41791234567")).toMatchObject({
      e164: "+41791234567",
      // Fuori dall'Italia il prefisso non ci dice se è mobile: non scartiamo.
      likelyMobile: true,
    });
  });

  it("marca un fisso come non mobile", () => {
    expect(normalizePhoneE164("0392123456")).toMatchObject({
      e164: "+390392123456",
      likelyMobile: false,
    });
  });

  it("scarta due numeri nello stesso campo", () => {
    expect(normalizePhoneE164("3331234567 / 3339876543")).toMatchObject({
      e164: null,
      reason: "too_long",
    });
  });

  it("scarta un numero troppo corto", () => {
    expect(normalizePhoneE164("+39")).toMatchObject({ e164: null, reason: "too_short" });
    expect(normalizePhoneE164("12345")).toMatchObject({ e164: null, reason: "too_short" });
  });
});

describe("sanitizeTemplateParam", () => {
  it("collassa gli spazi multipli", () => {
    expect(sanitizeTemplateParam("Pole    Dance")).toBe("Pole Dance");
  });

  it("rimuove newline e tab", () => {
    expect(sanitizeTemplateParam("Pole\nDance\tBase")).toBe("Pole Dance Base");
  });

  it("gestisce null e undefined", () => {
    expect(sanitizeTemplateParam(null)).toBe("");
    expect(sanitizeTemplateParam(undefined)).toBe("");
  });
});

describe("buildNome", () => {
  it("unisce nome e cognome", () => {
    expect(buildNome("Mario", "Rossi")).toBe("Mario Rossi");
  });

  it("non lascia spazi in coda con il cognome vuoto", () => {
    expect(buildNome("Mario", "")).toBe("Mario");
    expect(buildNome("Mario", null)).toBe("Mario");
  });

  it("è vuoto se manca del tutto il nome", () => {
    expect(buildNome("", "")).toBe("");
    expect(buildNome(null, undefined)).toBe("");
  });
});

describe("buildDemoLessonPayload", () => {
  const base = {
    nome: "Mario Rossi",
    phoneE164: "+393331234567",
    corso: "Corso Excel Avanzato",
    // 15 ottobre 2026, 18:00 ora di Roma (CEST, +2).
    startAt: new Date("2026-10-15T16:00:00Z"),
  };

  it("produce esattamente il body atteso dallo scenario Make", () => {
    expect(buildDemoLessonPayload({ ...base, kind: "booked" })).toEqual({
      tipo: "conferma",
      nome: "Mario Rossi",
      numero_di_telefono: "+393331234567",
      corso: "Corso Excel Avanzato",
      giorno: "15 ottobre 2026",
      orario: "18:00",
    });
  });

  it("espone esattamente sei chiavi, né una in più né una in meno", () => {
    // Make impara lo schema dal primo payload: cambiare le chiavi richiede un
    // "Redetermine data structure" sul webhook.
    const keys = Object.keys(buildDemoLessonPayload({ ...base, kind: "reminder" })).sort();
    expect(keys).toEqual([
      "corso",
      "giorno",
      "nome",
      "numero_di_telefono",
      "orario",
      "tipo",
    ]);
  });

  it("distingue i due eventi solo con il campo tipo", () => {
    const booked = buildDemoLessonPayload({ ...base, kind: "booked" });
    const reminder = buildDemoLessonPayload({ ...base, kind: "reminder" });

    expect(booked.tipo).toBe("conferma");
    expect(reminder.tipo).toBe("promemoria");
    expect({ ...booked, tipo: null }).toEqual({ ...reminder, tipo: null });
  });

  it("non contiene la chiave di autenticazione: sta solo nell'header", () => {
    const payload = buildDemoLessonPayload({ ...base, kind: "booked" }) as unknown as Record<string, unknown>;
    expect(payload.token).toBeUndefined();
    expect(payload.apiKey).toBeUndefined();
    expect(payload[MAKE_AUTH_HEADER]).toBeUndefined();
  });

  it("sanifica i valori: nessun newline, tab o spazio multiplo", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      kind: "booked",
      nome: "  Mario   Rossi \n",
      corso: "Pole\tDance    Base",
    });

    expect(payload.nome).toBe("Mario Rossi");
    expect(payload.corso).toBe("Pole Dance Base");
    for (const value of Object.values(payload)) {
      expect(value).not.toMatch(/[\n\t]/);
      expect(value).not.toMatch(/ {4}/);
      expect(value).toBe(value.trim());
    }
  });

  it("rifiuta un campo vuoto invece di mandarlo a Make", () => {
    // Meta rifiuta i template con parametri vuoti: i chiamanti devono scartare
    // a monte, quindi qui un campo vuoto è un bug da far emergere.
    expect(() => buildDemoLessonPayload({ ...base, kind: "booked", nome: "" })).toThrow(/nome/);
    expect(() => buildDemoLessonPayload({ ...base, kind: "booked", corso: "   " })).toThrow(/corso/);
  });

  it("usa l'ora di Roma anche a cavallo della mezzanotte UTC", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      kind: "reminder",
      startAt: new Date("2026-07-01T22:30:00Z"), // 00:30 del 2 luglio a Roma
    });
    expect(payload.giorno).toBe("2 luglio 2026");
    expect(payload.orario).toBe("00:30");
  });

  it("copre entrambi i kind della mappa TIPO_BY_KIND", () => {
    expect(Object.keys(TIPO_BY_KIND).sort()).toEqual(["booked", "reminder"]);
  });
});

// ──────────────────────────────────────────────
//  Infrastruttura condivisa per i test con I/O
// ──────────────────────────────────────────────

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const API_KEY = "chiave-super-segreta";

interface QueryDoc {
  id: string;
  data: Record<string, unknown>;
}

/**
 * Firestore finto con store in memoria: supporta sia `collection().doc()` (per
 * il log degli invii) sia `collection().where().get()` (per le query del cron),
 * tracciando le chiamate a `where` per poter asserire che non usiamo filtri
 * che richiederebbero un indice composito.
 */
function makeFakeDb(
  opts: {
    docs?: Record<string, Record<string, unknown>>;
    queries?: Record<string, QueryDoc[]>;
    createError?: Error;
    deleteError?: Error;
  } = {}
) {
  const store = new Map<string, Record<string, unknown>>();
  for (const [k, v] of Object.entries(opts.docs ?? {})) store.set(k, v);

  const whereCalls: Array<{ collection: string; field: string; op: string }> = [];
  const ops: string[] = [];
  const queues: Record<string, QueryDoc[][]> = {};
  for (const [name, docs] of Object.entries(opts.queries ?? {})) {
    queues[name] = [docs];
  }

  const db = {
    collection: (name: string) => {
      const query: Record<string, unknown> = {
        where: (field: string, op: string) => {
          whereCalls.push({ collection: name, field, op });
          return query;
        },
        limit: () => query,
        get: async () => {
          const docs = queues[name]?.[0] ?? [];
          return { docs: docs.map((d) => ({ id: d.id, data: () => d.data })) };
        },
        doc: (id: string) => {
          const key = `${name}/${id}`;
          return {
            create: async (data: Record<string, unknown>) => {
              ops.push(`create ${key}`);
              if (opts.createError) throw opts.createError;
              if (store.has(key)) {
                const err = new Error(`Document already exists: ${key}`) as Error & {
                  code?: number;
                };
                err.code = 6;
                throw err;
              }
              store.set(key, data);
            },
            get: async () => {
              ops.push(`get ${key}`);
              const data = store.get(key);
              return { exists: data != null, data: () => data };
            },
            update: async (patch: Record<string, unknown>) => {
              ops.push(`update ${key}`);
              store.set(key, { ...(store.get(key) ?? {}), ...patch });
            },
            delete: async () => {
              ops.push(`delete ${key}`);
              if (opts.deleteError) throw opts.deleteError;
              store.delete(key);
            },
          };
        },
      };
      return query;
    },
  };

  return { db: db as never, store, whereCalls, ops };
}

const samplePayload = () =>
  buildDemoLessonPayload({
    kind: "reminder",
    nome: "Mario Rossi",
    phoneE164: "+393331234567",
    corso: "Corso Excel Avanzato",
    startAt: new Date("2026-10-15T16:00:00Z"),
  });

/** Tutti gli argomenti passati al logger, serializzati, per cercarci i segreti. */
function allLoggedText(): string {
  const mock = logger as unknown as Record<string, jest.Mock>;
  return ["info", "warn", "error"]
    .flatMap((level) => mock[level].mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

describe("postToMake", () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  /** Make risponde con il testo "Accepted", non con JSON. */
  function mockAccepted(status = 200) {
    fetchMock.mockResolvedValue({
      ok: status >= 200 && status < 300,
      status,
      text: async () => "Accepted",
    });
  }

  it("manda la chiave nell'header Demo-Reminder e non nel body", async () => {
    mockAccepted();
    const payload = samplePayload();

    await postToMake(WEBHOOK_URL, API_KEY, payload);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(WEBHOOK_URL);
    expect(init.method).toBe("POST");
    expect(init.headers[MAKE_AUTH_HEADER]).toBe(API_KEY);
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.body).toBe(JSON.stringify(payload));
    expect(init.body).not.toContain(API_KEY);
  });

  it("imposta un timeout sulla richiesta", async () => {
    mockAccepted();
    await postToMake(WEBHOOK_URL, API_KEY, samplePayload(), { timeoutMs: 500 });
    expect(fetchMock.mock.calls[0][1].signal).toBeDefined();
  });

  it("gestisce la risposta 200 testuale senza deserializzare il corpo", async () => {
    mockAccepted();
    const res = await postToMake(WEBHOOK_URL, API_KEY, samplePayload());
    expect(res).toEqual({ ok: true, status: 200 });
  });

  it("ritorna ok:false su risposta di errore, senza lanciare", async () => {
    mockAccepted(410); // scenario Make disattivato
    const res = await postToMake(WEBHOOK_URL, API_KEY, samplePayload());
    expect(res).toEqual({ ok: false, status: 410 });
  });

  it("ritorna ok:false su errore di rete o timeout, senza lanciare", async () => {
    fetchMock.mockRejectedValue(new Error("The operation was aborted due to timeout"));
    const res = await postToMake(WEBHOOK_URL, API_KEY, samplePayload());
    expect(res).toEqual({ ok: false, status: 0 });
  });

  it("non scrive mai URL né chiave nei log", async () => {
    mockAccepted(500);
    await postToMake(WEBHOOK_URL, API_KEY, samplePayload());
    fetchMock.mockRejectedValue(new Error(`connect ECONNREFUSED ${WEBHOOK_URL} key=${API_KEY}`));
    await postToMake(WEBHOOK_URL, API_KEY, samplePayload());

    const logged = allLoggedText();
    expect(logged).not.toContain(WEBHOOK_URL);
    expect(logged).not.toContain(API_KEY);
    // …ma l'host resta, che è utile e non è un segreto.
    expect(logged).toContain("hook.eu1.make.com");
  });
});

describe("demoLogDocId", () => {
  it("compone kind_userId_courseId, senza data", () => {
    expect(demoLogDocId("booked", "u1", "c1")).toBe("booked_u1_c1");
    expect(demoLogDocId("reminder", "u1", "c1")).toBe("reminder_u1_c1");
  });

  it("rifiuta id vuoti o con slash, che romperebbero il path Firestore", () => {
    expect(() => demoLogDocId("booked", "", "c1")).toThrow();
    expect(() => demoLogDocId("booked", "u1", "")).toThrow();
    expect(() => demoLogDocId("booked", "a/b", "c1")).toThrow();
  });
});

describe("claimSend / confirmSend / releaseSend", () => {
  const now = new Date("2026-10-14T17:00:00Z");

  afterEach(() => jest.clearAllMocks());

  it("prenota l'invio la prima volta", async () => {
    const { db, store } = makeFakeDb();
    await expect(claimSend(db, "reminder", "u1", "c1", now)).resolves.toBe(true);

    const doc = store.get(`${DEMO_LOG_COLLECTION}/reminder_u1_c1`);
    expect(doc).toMatchObject({ kind: "reminder", userId: "u1", courseId: "c1", ok: false });
    // Nessun dato personale nel log.
    expect(JSON.stringify(doc)).not.toContain("+39");
  });

  it("rifiuta la seconda prenotazione della stessa coppia", async () => {
    const { db } = makeFakeDb();
    await claimSend(db, "reminder", "u1", "c1", now);
    await expect(claimSend(db, "reminder", "u1", "c1", now)).resolves.toBe(false);
  });

  it("distingue conferma e promemoria della stessa coppia", async () => {
    const { db } = makeFakeDb();
    await expect(claimSend(db, "booked", "u1", "c1", now)).resolves.toBe(true);
    await expect(claimSend(db, "reminder", "u1", "c1", now)).resolves.toBe(true);
  });

  it("riconosce ALREADY_EXISTS anche dal solo messaggio", async () => {
    const { db } = makeFakeDb({ createError: new Error("6 ALREADY_EXISTS: entity already exists") });
    await expect(claimSend(db, "booked", "u1", "c1", now)).resolves.toBe(false);
  });

  it("propaga gli altri errori di Firestore", async () => {
    const { db } = makeFakeDb({ createError: new Error("PERMISSION_DENIED") });
    await expect(claimSend(db, "booked", "u1", "c1", now)).rejects.toThrow("PERMISSION_DENIED");
  });

  it("confirmSend marca l'invio come riuscito", async () => {
    const { db, store } = makeFakeDb();
    await claimSend(db, "booked", "u1", "c1", now);
    await confirmSend(db, "booked", "u1", "c1");
    expect(store.get(`${DEMO_LOG_COLLECTION}/booked_u1_c1`)).toMatchObject({ ok: true });
  });

  it("releaseSend cancella il claim, permettendo un nuovo tentativo", async () => {
    const { db, store } = makeFakeDb();
    await claimSend(db, "booked", "u1", "c1", now);
    await releaseSend(db, "booked", "u1", "c1");

    expect(store.has(`${DEMO_LOG_COLLECTION}/booked_u1_c1`)).toBe(false);
    await expect(claimSend(db, "booked", "u1", "c1", now)).resolves.toBe(true);
  });

  it("releaseSend non lancia se la cancellazione fallisce", async () => {
    const { db } = makeFakeDb({ deleteError: new Error("UNAVAILABLE") });
    await expect(releaseSend(db, "booked", "u1", "c1")).resolves.toBeUndefined();
  });
});

describe("wasNotifiedToday", () => {
  const now = new Date("2026-10-14T17:00:00Z"); // 19:00 del 14 ottobre a Roma

  it("è falso se non è mai partita una conferma", async () => {
    const { db } = makeFakeDb();
    await expect(wasNotifiedToday(db, "u1", "c1", now)).resolves.toBe(false);
  });

  it("è vero se la conferma è partita nello stesso giorno romano", async () => {
    const { db } = makeFakeDb({
      docs: {
        [`${DEMO_LOG_COLLECTION}/booked_u1_c1`]: {
          sentAt: Timestamp.fromDate(new Date("2026-10-14T08:00:00Z")),
        },
      },
    });
    await expect(wasNotifiedToday(db, "u1", "c1", now)).resolves.toBe(true);
  });

  it("è falso se la conferma è di un giorno precedente", async () => {
    const { db } = makeFakeDb({
      docs: {
        [`${DEMO_LOG_COLLECTION}/booked_u1_c1`]: {
          sentAt: Timestamp.fromDate(new Date("2026-10-13T08:00:00Z")),
        },
      },
    });
    await expect(wasNotifiedToday(db, "u1", "c1", now)).resolves.toBe(false);
  });

  it("guarda solo la conferma, non il promemoria", async () => {
    const { db } = makeFakeDb({
      docs: {
        [`${DEMO_LOG_COLLECTION}/reminder_u1_c1`]: {
          sentAt: Timestamp.fromDate(new Date("2026-10-14T08:00:00Z")),
        },
      },
    });
    await expect(wasNotifiedToday(db, "u1", "c1", now)).resolves.toBe(false);
  });
});

// ──────────────────────────────────────────────
//  Fixture per handler e cron
// ──────────────────────────────────────────────

const NOW = new Date("2026-10-14T17:00:00Z"); // 19:00 del 14 ottobre a Roma

/** Corso di domani (15 ottobre) alle 18:00 ora di Roma. */
const domani18 = () => Timestamp.fromDate(new Date("2026-10-15T16:00:00Z"));

const trialUser = (over: Record<string, unknown> = {}) => ({
  uid: "u1",
  name: "Mario",
  lastName: "Rossi",
  numeroTelefono: "3331234567",
  tipologiaIscrizione: "ABBONAMENTO_PROVA",
  isActive: true,
  courses: ["c1"],
  ...over,
});

const courseDoc = (over: Record<string, unknown> = {}) => ({
  uid: "c1",
  name: "Corso Excel Avanzato",
  startDate: domani18(),
  reminderEnabled: true,
  ...over,
});

function makeDeps(
  fake: ReturnType<typeof makeFakeDb>,
  post = jest.fn().mockResolvedValue({ ok: true, status: 200 })
) {
  return {
    deps: {
      db: fake.db,
      webhookUrl: WEBHOOK_URL,
      apiKey: API_KEY,
      post,
      now: NOW,
    },
    post,
  };
}

describe("mapDemoCourseDoc", () => {
  it("usa il campo uid quando presente", () => {
    const c = mapDemoCourseDoc({ id: "doc-1", data: () => courseDoc({ uid: "c9" }) });
    expect(c).toMatchObject({ uid: "c9", docId: "doc-1", reminderEnabled: true });
    expect(c.startAt?.toISOString()).toBe("2026-10-15T16:00:00.000Z");
  });

  it("ricade su id e poi su doc.id per i documenti storici senza uid", () => {
    const senzaUid = { name: "X", startDate: domani18(), id: "c-legacy" };
    expect(mapDemoCourseDoc({ id: "doc-2", data: () => senzaUid }).uid).toBe("c-legacy");

    const soloDocId = { name: "X", startDate: domani18() };
    expect(mapDemoCourseDoc({ id: "doc-3", data: () => soloDocId }).uid).toBe("doc-3");
  });

  it("gestisce un corso senza data", () => {
    expect(mapDemoCourseDoc({ id: "d", data: () => ({ name: "X" }) }).startAt).toBeNull();
  });
});

describe("mapDemoUserDoc", () => {
  it("applica i default: isActive true, courses vuoto", () => {
    const u = mapDemoUserDoc({ id: "u9", data: () => ({ name: "Test" }) });
    expect(u).toEqual({
      uid: "u9",
      name: "Test",
      lastName: "",
      numeroTelefono: null,
      tipologiaIscrizione: null,
      isActive: true,
      courses: [],
    });
  });
});

describe("checkRecipient", () => {
  const course = () => mapDemoCourseDoc({ id: "c1", data: () => courseDoc() });
  const user = (over: Record<string, unknown> = {}) =>
    mapDemoUserDoc({ id: "u1", data: () => trialUser(over) });

  it("accetta un utente di prova con numero di cellulare", () => {
    expect(checkRecipient("reminder", user(), course(), NOW)).toEqual({
      ok: true,
      nome: "Mario Rossi",
      corso: "Corso Excel Avanzato",
      phoneE164: "+393331234567",
      startAt: new Date("2026-10-15T16:00:00Z"),
    });
  });

  it.each([
    ["not_trial", { tipologiaIscrizione: "ABBONAMENTO_MENSILE" }],
    ["inactive", { isActive: false }],
    ["no_phone", { numeroTelefono: null }],
    ["no_phone", { numeroTelefono: "-" }],
    ["not_mobile", { numeroTelefono: "0392123456" }],
    ["not_numeric", { numeroTelefono: "n/d" }],
    ["no_name", { name: "", lastName: "" }],
  ])("scarta con reason %s", (reason, over) => {
    expect(checkRecipient("reminder", user(over), course(), NOW)).toEqual({ ok: false, reason });
  });

  it("scarta un corso già iniziato", () => {
    const ieri = mapDemoCourseDoc({
      id: "c1",
      data: () => courseDoc({ startDate: Timestamp.fromDate(new Date("2026-10-13T16:00:00Z")) }),
    });
    expect(checkRecipient("booked", user(), ieri, NOW)).toEqual({
      ok: false,
      reason: "course_in_past",
    });
  });

  it("scarta un corso senza nome", () => {
    const anonimo = mapDemoCourseDoc({ id: "c1", data: () => courseDoc({ name: "  " }) });
    expect(checkRecipient("booked", user(), anonimo, NOW)).toEqual({
      ok: false,
      reason: "no_course_name",
    });
  });

  it("reminderEnabled:false blocca il promemoria ma non la conferma", () => {
    const noReminder = mapDemoCourseDoc({
      id: "c1",
      data: () => courseDoc({ reminderEnabled: false }),
    });
    expect(checkRecipient("reminder", user(), noReminder, NOW)).toEqual({
      ok: false,
      reason: "reminder_disabled",
    });
    expect(checkRecipient("booked", user(), noReminder, NOW)).toMatchObject({ ok: true });
  });
});

describe("notifyDemoLessonBookedHandler", () => {
  afterEach(() => jest.clearAllMocks());

  const auth = (uid: string) => ({ auth: { uid }, data: { userId: "u1", courseId: "c1" } });

  function scenario(over: { users?: Record<string, Record<string, unknown>>; courses?: Record<string, Record<string, unknown>> } = {}) {
    const fake = makeFakeDb({
      docs: {
        "users/u1": trialUser(),
        ...Object.fromEntries(
          Object.entries(over.users ?? {}).map(([k, v]) => [`users/${k}`, v])
        ),
        "courses/c1": courseDoc(),
        ...Object.fromEntries(
          Object.entries(over.courses ?? {}).map(([k, v]) => [`courses/${k}`, v])
        ),
      },
    });
    return { fake, ...makeDeps(fake) };
  }

  it("rifiuta le chiamate non autenticate", async () => {
    const { deps } = scenario();
    await expect(
      notifyDemoLessonBookedHandler({ data: { userId: "u1", courseId: "c1" } }, deps)
    ).rejects.toThrow(HttpsError);
  });

  it("rifiuta un payload incompleto", async () => {
    const { deps } = scenario();
    await expect(
      notifyDemoLessonBookedHandler({ auth: { uid: "u1" }, data: { userId: "u1" } }, deps)
    ).rejects.toThrow(/courseId/);
    await expect(
      notifyDemoLessonBookedHandler({ auth: { uid: "u1" }, data: null }, deps)
    ).rejects.toThrow(HttpsError);
  });

  it("invia quando il chiamante è l'utente stesso", async () => {
    const { deps, post } = scenario();
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0][2]).toMatchObject({
      tipo: "conferma",
      nome: "Mario Rossi",
      numero_di_telefono: "+393331234567",
      giorno: "15 ottobre 2026",
      orario: "18:00",
    });
  });

  it("nega a un utente normale di notificare qualcun altro", async () => {
    const { deps, post } = scenario({ users: { admin: { role: "User" } } });
    await expect(notifyDemoLessonBookedHandler(auth("admin"), deps)).rejects.toThrow(
      /Admin e Trainer/
    );
    expect(post).not.toHaveBeenCalled();
  });

  it.each([["Admin"], ["Trainer"]])("permette a un %s di notificare un altro utente", async (role) => {
    const { deps, post } = scenario({ users: { staff: { role } } });
    await expect(notifyDemoLessonBookedHandler(auth("staff"), deps)).resolves.toEqual({
      sent: true,
    });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("nega se il chiamante non ha un documento utente", async () => {
    const { deps } = scenario();
    await expect(notifyDemoLessonBookedHandler(auth("ignoto"), deps)).rejects.toThrow(
      /Admin e Trainer/
    );
  });

  it.each([
    ["not_trial", { tipologiaIscrizione: "ABBONAMENTO_ANNUALE" }],
    ["inactive", { isActive: false }],
    ["no_phone", { numeroTelefono: null }],
    ["not_mobile", { numeroTelefono: "0392123456" }],
    ["no_name", { name: "", lastName: "" }],
  ])("non chiama il webhook quando scarta con %s", async (reason, over) => {
    const fake = makeFakeDb({
      docs: { "users/u1": trialUser(over), "courses/c1": courseDoc() },
    });
    const { deps, post } = makeDeps(fake);
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({
      sent: false,
      reason,
    });
    expect(post).not.toHaveBeenCalled();
  });

  it("segnala l'utente inesistente", async () => {
    const fake = makeFakeDb({ docs: { "courses/c1": courseDoc() } });
    const { deps, post } = makeDeps(fake);
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({
      sent: false,
      reason: "user_not_found",
    });
    expect(post).not.toHaveBeenCalled();
  });

  it("segnala il corso inesistente", async () => {
    const fake = makeFakeDb({ docs: { "users/u1": trialUser() } });
    const { deps, post } = makeDeps(fake);
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({
      sent: false,
      reason: "course_not_found",
    });
    expect(post).not.toHaveBeenCalled();
  });

  it("trova un corso il cui uid differisce dall'id del documento", async () => {
    const fake = makeFakeDb({
      docs: { "users/u1": trialUser() },
      queries: { courses: [{ id: "doc-legacy", data: courseDoc({ uid: "c1" }) }] },
    });
    const { deps, post } = makeDeps(fake);
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("non invia due volte per la stessa coppia utente/corso", async () => {
    const { deps, post } = scenario();
    await notifyDemoLessonBookedHandler(auth("u1"), deps);
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({
      sent: false,
      reason: "already_sent",
    });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("rilascia il claim se la POST fallisce, così un nuovo tentativo è possibile", async () => {
    const fake = makeFakeDb({ docs: { "users/u1": trialUser(), "courses/c1": courseDoc() } });
    const post = jest.fn().mockResolvedValue({ ok: false, status: 500 });
    const { deps } = makeDeps(fake, post);

    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toMatchObject({
      sent: false,
      failed: true,
    });
    expect(fake.store.has(`${DEMO_LOG_COLLECTION}/booked_u1_c1`)).toBe(false);
    expect(fake.ops).toContain(`delete ${DEMO_LOG_COLLECTION}/booked_u1_c1`);

    post.mockResolvedValue({ ok: true, status: 200 });
    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).resolves.toEqual({ sent: true });
  });

  it("rilascia il claim anche se la POST lancia", async () => {
    const fake = makeFakeDb({ docs: { "users/u1": trialUser(), "courses/c1": courseDoc() } });
    const post = jest.fn().mockRejectedValue(new Error("boom"));
    const { deps } = makeDeps(fake, post);

    await expect(notifyDemoLessonBookedHandler(auth("u1"), deps)).rejects.toThrow("boom");
    expect(fake.store.has(`${DEMO_LOG_COLLECTION}/booked_u1_c1`)).toBe(false);
  });

  it("registra l'invio con soli identificativi, senza dati personali", async () => {
    const { fake, deps } = scenario();
    await notifyDemoLessonBookedHandler(auth("u1"), deps);

    const doc = fake.store.get(`${DEMO_LOG_COLLECTION}/booked_u1_c1`);
    expect(doc).toMatchObject({ kind: "booked", userId: "u1", courseId: "c1", ok: true });
    const serialized = JSON.stringify(doc);
    expect(serialized).not.toContain("Mario");
    expect(serialized).not.toContain("3331234567");
  });
});

describe("runDemoLessonReminders", () => {
  afterEach(() => jest.clearAllMocks());

  function cronFake(
    users: Array<{ id: string; data: Record<string, unknown> }>,
    courses: Array<{ id: string; data: Record<string, unknown> }>,
    docs: Record<string, Record<string, unknown>> = {}
  ) {
    const fake = makeFakeDb({ docs, queries: { users, courses } });
    return { fake, ...makeDeps(fake) };
  }

  const u = (id: string, over: Record<string, unknown> = {}) => ({
    id,
    data: trialUser({ uid: id, ...over }),
  });
  const c = (id: string, over: Record<string, unknown> = {}) => ({
    id,
    data: courseDoc({ uid: id, ...over }),
  });

  it("interroga courses solo su startDate e users solo su tipologiaIscrizione", async () => {
    const { fake, deps } = cronFake([], []);
    await runDemoLessonReminders(deps);

    const byCollection = (name: string) =>
      fake.whereCalls.filter((w) => w.collection === name).map((w) => w.field);

    expect(new Set(byCollection("courses"))).toEqual(new Set(["startDate"]));
    expect(new Set(byCollection("users"))).toEqual(new Set(["tipologiaIscrizione"]));
    // Nessun filtro che richiederebbe un indice composito.
    expect(fake.whereCalls.some((w) => w.op.includes("array-contains"))).toBe(false);
  });

  it("invia solo alle coppie utente/corso effettivamente iscritte", async () => {
    const { deps, post } = cronFake(
      [
        u("u1", { courses: ["c1"] }),
        u("u2", { courses: ["c2"] }),
        u("u3", { courses: ["c-altro"] }),
      ],
      [c("c1"), c("c2")]
    );

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ trialUsersRead: 3, coursesTomorrow: 2, candidates: 2, sent: 2 });
    expect(post).toHaveBeenCalledTimes(2);
    expect(post.mock.calls.every((call) => call[2].tipo === "promemoria")).toBe(true);
  });

  it("ignora i corsi che non cadono nel giorno target", async () => {
    const dopodomani = Timestamp.fromDate(new Date("2026-10-16T16:00:00Z"));
    const { deps, post } = cronFake(
      [u("u1", { courses: ["c1", "c2"] })],
      [c("c1"), c("c2", { startDate: dopodomani })]
    );

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ coursesTomorrow: 1, candidates: 1, sent: 1 });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("salta i corsi con reminderEnabled disattivato", async () => {
    const { deps, post } = cronFake(
      [u("u1", { courses: ["c1"] })],
      [c("c1", { reminderEnabled: false })]
    );

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 1, sent: 0, skipped: 1, failed: 0 });
    expect(post).not.toHaveBeenCalled();
  });

  it.each([
    ["utente disattivato", { isActive: false }],
    ["senza telefono", { numeroTelefono: null }],
    ["con numero fisso", { numeroTelefono: "0392123456" }],
    ["senza nome", { name: "", lastName: "" }],
  ])("salta l'utente %s senza fermare gli altri", async (_label, over) => {
    const { deps, post } = cronFake(
      [u("u1", { courses: ["c1"], ...over }), u("u2", { courses: ["c1"] })],
      [c("c1")]
    );

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 2, sent: 1, skipped: 1, failed: 0 });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("riconosce l'iscrizione a un corso storico senza uid", async () => {
    const { deps, post } = cronFake(
      [u("u1", { courses: ["doc-legacy"] })],
      [{ id: "doc-legacy", data: { name: "Corso", startDate: domani18(), reminderEnabled: true } }]
    );

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 1, sent: 1 });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("conta come failed una POST rifiutata, senza interrompere il run", async () => {
    const post = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 410 })
      .mockResolvedValue({ ok: true, status: 200 });
    const fake = makeFakeDb({
      queries: { users: [u("u1", { courses: ["c1"] }), u("u2", { courses: ["c1"] })], courses: [c("c1")] },
    });
    const { deps } = makeDeps(fake, post);

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 2, sent: 1, failed: 1, skipped: 0 });
    // Il claim del destinatario fallito è stato rilasciato.
    expect(fake.store.has(`${DEMO_LOG_COLLECTION}/reminder_u1_c1`)).toBe(false);
    expect(fake.store.has(`${DEMO_LOG_COLLECTION}/reminder_u2_c1`)).toBe(true);
  });

  it("un errore inatteso su un destinatario non interrompe il run", async () => {
    const post = jest
      .fn()
      .mockRejectedValueOnce(new Error("boom"))
      .mockResolvedValue({ ok: true, status: 200 });
    const fake = makeFakeDb({
      queries: { users: [u("u1", { courses: ["c1"] }), u("u2", { courses: ["c1"] })], courses: [c("c1")] },
    });
    const { deps } = makeDeps(fake, post);

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 2, sent: 1, failed: 1 });
  });

  it("sopprime il promemoria se la conferma è già partita oggi", async () => {
    const { deps, post } = cronFake([u("u1", { courses: ["c1"] })], [c("c1")], {
      [`${DEMO_LOG_COLLECTION}/booked_u1_c1`]: {
        sentAt: Timestamp.fromDate(new Date("2026-10-14T09:00:00Z")),
      },
    });

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 1, sent: 0, skipped: 1 });
    expect(post).not.toHaveBeenCalled();
  });

  it("manda il promemoria se la conferma è di un giorno precedente", async () => {
    const { deps, post } = cronFake([u("u1", { courses: ["c1"] })], [c("c1")], {
      [`${DEMO_LOG_COLLECTION}/booked_u1_c1`]: {
        sentAt: Timestamp.fromDate(new Date("2026-10-12T09:00:00Z")),
      },
    });

    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ candidates: 1, sent: 1 });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it("non manda due volte il promemoria per la stessa coppia", async () => {
    const { deps, post } = cronFake([u("u1", { courses: ["c1"] })], [c("c1")]);

    await runDemoLessonReminders(deps);
    const res = await runDemoLessonReminders(deps);

    expect(res).toMatchObject({ sent: 0, skipped: 1 });
    expect(post).toHaveBeenCalledTimes(1);
  });
});

describe("sendTestDemoLessonWebhookHandler", () => {
  afterEach(() => jest.clearAllMocks());

  it("rifiuta le chiamate non autenticate", async () => {
    const { deps } = makeDeps(makeFakeDb());
    await expect(
      sendTestDemoLessonWebhookHandler({ data: { numeroTelefono: "3331234567" } }, deps)
    ).rejects.toThrow(HttpsError);
  });

  it("richiede il numero di telefono", async () => {
    const { deps } = makeDeps(makeFakeDb());
    await expect(
      sendTestDemoLessonWebhookHandler({ auth: { uid: "u1" }, data: {} }, deps)
    ).rejects.toThrow(/numeroTelefono/);
  });

  it("rifiuta un numero non valido spiegando il motivo", async () => {
    const { deps } = makeDeps(makeFakeDb());
    await expect(
      sendTestDemoLessonWebhookHandler({ auth: { uid: "u1" }, data: { numeroTelefono: "n/d" } }, deps)
    ).rejects.toThrow(/not_numeric/);
  });

  it("manda un payload sintetico al numero indicato, senza toccare Firestore", async () => {
    const fake = makeFakeDb();
    const { deps, post } = makeDeps(fake);

    const res = await sendTestDemoLessonWebhookHandler(
      { auth: { uid: "u1" }, data: { kind: "reminder", numeroTelefono: "3339876543" } },
      deps
    );

    expect(res).toMatchObject({ ok: true, status: 200 });
    expect(post.mock.calls[0][2]).toEqual({
      tipo: "promemoria",
      nome: "Test Test",
      numero_di_telefono: "+393339876543",
      corso: "Lezione di prova",
      giorno: "15 ottobre 2026",
      orario: "19:00",
    });
    // Il payload torna al chiamante, così la DebugEmailPage può mostrarlo.
    expect(res.payload).toEqual(post.mock.calls[0][2]);
    // Nessuna scrittura né lettura: il test non inquina il log degli invii.
    expect(fake.ops).toEqual([]);
    expect(fake.store.size).toBe(0);
  });

  it("usa nome, corso, giorno e orario passati dal chiamante", async () => {
    const { deps, post } = makeDeps(makeFakeDb());

    await sendTestDemoLessonWebhookHandler(
      {
        auth: { uid: "u1" },
        data: {
          numeroTelefono: "3339876543",
          nome: "Mario Rossi",
          corso: "Pole Dance Base",
          giorno: "28 aprile 2026",
          orario: "10:00",
        },
      },
      deps
    );

    expect(post.mock.calls[0][2]).toMatchObject({
      nome: "Mario Rossi",
      corso: "Pole Dance Base",
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
  });

  it("ricade sui default quando i campi arrivano vuoti", async () => {
    const { deps, post } = makeDeps(makeFakeDb());

    await sendTestDemoLessonWebhookHandler(
      {
        auth: { uid: "u1" },
        data: { numeroTelefono: "3339876543", nome: "  ", corso: "", giorno: " ", orario: "" },
      },
      deps
    );

    expect(post.mock.calls[0][2]).toMatchObject({
      nome: "Test Test",
      corso: "Lezione di prova",
      giorno: "15 ottobre 2026",
      orario: "19:00",
    });
  });

  it("default al tipo conferma", async () => {
    const { deps, post } = makeDeps(makeFakeDb());
    await sendTestDemoLessonWebhookHandler(
      { auth: { uid: "u1" }, data: { numeroTelefono: "3339876543" } },
      deps
    );
    expect(post.mock.calls[0][2].tipo).toBe("conferma");
  });
});
