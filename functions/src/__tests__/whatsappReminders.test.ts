import { Timestamp } from "firebase-admin/firestore";
import { WhatsappDeps } from "../whatsapp/demoLesson";
import { PostResult } from "../whatsapp/makeClient";
import { DemoLessonPayload } from "../whatsapp/payload";
import {
  ARRAY_CONTAINS_ANY_LIMIT,
  MAX_CONCURRENT_SENDS,
  chunk,
  runDemoLessonReminders,
} from "../whatsapp/reminders";
import { DEMO_LOG_COLLECTION } from "../whatsapp/sendLog";
import { Data, Store, makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

// Il cron gira il 14 ottobre 2026 alle 19:00 ora di Roma (CEST).
const SCHEDULED = Date.UTC(2026, 9, 14, 17);
const DOMANI_18 = Date.UTC(2026, 9, 15, 16);
const DAY = 86_400_000;
const FAR_DEADLINE = Number.MAX_SAFE_INTEGER;

const phone = (n: number) => `3331234${String(n).padStart(3, "0")}`;

// Snapshot validi per recordFromDoc (stessa forma di enrollmentHandlers.test.ts).
const trialSnapshot = (): Data => ({
  id: "trial",
  planKey: "open_trial_1i_30d",
  family: "OPEN",
  billingMode: "ENTRIES",
  courseTypeTags: ["Open"],
  weeklyFrequency: null,
  remainingEntries: 1,
  startDate: Timestamp.fromMillis(SCHEDULED - DAY),
  endDate: Timestamp.fromMillis(SCHEDULED + 29 * DAY),
});

const openSnapshot = (): Data => ({
  id: "sub-open",
  planKey: "open_2x_3m",
  family: "OPEN",
  billingMode: "FREQUENCY",
  courseTypeTags: ["Open"],
  weeklyFrequency: 2,
  remainingEntries: null,
  startDate: Timestamp.fromMillis(Date.UTC(2026, 0, 1)),
  endDate: Timestamp.fromMillis(Date.UTC(2026, 11, 31)),
});

const baseUser = (n: number, courses: string[], over: Data = {}): Data => ({
  uid: `u${n}`,
  name: "Utente",
  lastName: `N${n}`,
  numeroTelefono: phone(n),
  isActive: true,
  courses,
  ...over,
});

/** Utente di prova V2 (abbonamento vivo sul piano di prova). */
const trialV2 = (n: number, courses: string[] = ["c1"], over: Data = {}) =>
  baseUser(n, courses, { subscriptionModelVersion: 2, activeSubscriptions: [trialSnapshot()], ...over });

/** Utente di prova legacy (nessuno snapshot, tipologia PROVA). */
const trialLegacy = (n: number, courses: string[] = ["c1"], over: Data = {}) =>
  baseUser(n, courses, { tipologiaIscrizione: "ABBONAMENTO_PROVA", ...over });

const courseDoc = (uid: string, over: Data = {}): Data => ({
  uid,
  name: `Corso ${uid}`,
  startDate: Timestamp.fromMillis(DOMANI_18),
  reminderEnabled: true,
  ...over,
});

const ok: PostResult = { ok: true, status: 200 };

function setup(
  store: Store,
  opts: { post?: jest.Mock<Promise<PostResult>, [string, string, DemoLessonPayload]>; nowMillis?: number } = {}
) {
  const fake = makeWhatsappDb(store);
  const post =
    opts.post ?? jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(async () => ok);
  const deps: WhatsappDeps = {
    db: fake.db,
    webhookUrl: "https://hook.eu1.make.com/abc",
    apiKey: "chiave",
    post,
    nowMillis: opts.nowMillis ?? SCHEDULED + 1000,
    env: {},
    wait: async () => undefined,
  };
  const phonesPosted = () => post.mock.calls.map((call) => call[2].numero_di_telefono);
  return { fake, deps, post, phonesPosted };
}

const run = (deps: WhatsappDeps, over: { deadlineMillis?: number; now?: () => number } = {}) =>
  runDemoLessonReminders(deps, {
    scheduledAtMillis: SCHEDULED,
    deadlineMillis: over.deadlineMillis ?? FAR_DEADLINE,
    now: over.now,
  });

afterEach(() => jest.clearAllMocks());

describe("chunk", () => {
  test("spezza una lista in blocchi della dimensione indicata", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([], 30)).toEqual([]);
    expect(ARRAY_CONTAINS_ANY_LIMIT).toBe(30);
    expect(MAX_CONCURRENT_SENDS).toBe(10);
  });
});

describe("runDemoLessonReminders", () => {
  test("usa solo filtri Firestore a campo singolo (nessun indice composito)", async () => {
    const { fake, deps } = setup({ users: { u1: trialV2(1) }, courses: { c1: courseDoc("c1") } });
    await run(deps);
    const byCollection = fake.whereCalls.map(({ collection, field, op }) => `${collection}.${field} ${op}`);
    expect(byCollection).toEqual([
      "courses.startDate >=",
      "courses.startDate <=",
      "users.courses array-contains-any",
    ]);
    const [start, end] = fake.whereCalls.slice(0, 2).map((c) => (c.value as Timestamp).toMillis());
    expect(start).toBe(Date.UTC(2026, 9, 14, 22)); // 15 ottobre 00:00 CEST
    expect(end).toBe(Date.UTC(2026, 9, 15, 22) - 1);
  });

  test("nessun corso domani: nessuna query sugli utenti e nessun invio", async () => {
    const { fake, deps, post } = setup({
      users: { u1: trialV2(1, ["c-oggi"]) },
      courses: { "c-oggi": courseDoc("c-oggi", { startDate: Timestamp.fromMillis(SCHEDULED + 3600_000) }) },
    });
    await expect(run(deps)).resolves.toMatchObject({
      coursesTomorrow: 0,
      candidates: 0,
      sent: 0,
    });
    expect(fake.whereCalls.some((c) => c.collection === "users")).toBe(false);
    expect(post).not.toHaveBeenCalled();
  });

  test("scrive agli utenti di prova V2 e legacy, con tipo promemoria", async () => {
    const { deps, post, phonesPosted } = setup({
      users: { u1: trialV2(1), u2: trialLegacy(2) },
      courses: { c1: courseDoc("c1") },
    });
    await expect(run(deps)).resolves.toMatchObject({ candidates: 2, sent: 2, skipped: 0, failed: 0 });
    expect(phonesPosted().sort()).toEqual([`+39${phone(1)}`, `+39${phone(2)}`]);
    expect(post.mock.calls.every((call) => call[2].tipo === "promemoria")).toBe(true);
  });

  test("non scrive al cliente convertito che ha ancora la tipologia PROVA", async () => {
    const { deps, post } = setup({
      users: {
        u1: baseUser(1, ["c1"], { tipologiaIscrizione: "ABBONAMENTO_PROVA", activeSubscriptions: [openSnapshot()] }),
        u2: baseUser(2, ["c1"], { tipologiaIscrizione: "PACCHETTO_ENTRATE" }),
        u3: baseUser(3, ["c1"], { tipologiaIscrizione: "ABBONAMENTO_PROVA", subscriptionModelVersion: 2 }),
      },
      courses: { c1: courseDoc("c1") },
    });
    await expect(run(deps)).resolves.toMatchObject({ usersRead: 3, candidates: 0, sent: 0 });
    expect(post).not.toHaveBeenCalled();
  });

  test("uno snapshot illeggibile non ferma il run", async () => {
    const { deps, phonesPosted } = setup({
      users: {
        u1: baseUser(1, ["c1"], { activeSubscriptions: "rotto" }),
        u2: baseUser(2, ["c1"], { activeSubscriptions: [{ id: "x", planKey: "sconosciuto" }] }),
        u3: trialLegacy(3),
      },
      courses: { c1: courseDoc("c1") },
    });
    await expect(run(deps)).resolves.toMatchObject({ usersRead: 3, sent: 1, failed: 2 });
    expect(phonesPosted()).toEqual([`+39${phone(3)}`]);
  });

  test("reminderEnabled:false salta il promemoria", async () => {
    const { deps, post } = setup({
      users: { u1: trialV2(1) },
      courses: { c1: courseDoc("c1", { reminderEnabled: false }) },
    });
    await expect(run(deps)).resolves.toMatchObject({ candidates: 1, sent: 0, skipped: 1 });
    expect(post).not.toHaveBeenCalled();
  });

  test("spezza le query oltre i 30 corsi e non duplica gli utenti", async () => {
    const courses: Record<string, Data> = {};
    for (let i = 1; i <= 31; i++) courses[`c${i}`] = courseDoc(`c${i}`);
    const { fake, deps, phonesPosted } = setup({
      users: {
        // Iscritto a un corso del primo blocco e a uno del secondo.
        u1: trialV2(1, ["c1", "c31"]),
        u2: trialLegacy(2, ["c31"]),
      },
      courses,
    });
    await expect(run(deps)).resolves.toMatchObject({
      coursesTomorrow: 31,
      usersRead: 2,
      candidates: 3,
      sent: 3,
    });
    const userQueries = fake.whereCalls.filter((c) => c.collection === "users");
    expect(userQueries).toHaveLength(2);
    expect(userQueries.map((c) => (c.value as unknown[]).length).sort((a, b) => a - b)).toEqual([1, 30]);
    expect(phonesPosted().sort()).toEqual([`+39${phone(1)}`, `+39${phone(1)}`, `+39${phone(2)}`].sort());
    expect(Object.keys(fake.store[DEMO_LOG_COLLECTION]).sort()).toEqual([
      "reminder_u1_c1",
      "reminder_u1_c31",
      "reminder_u2_c31",
    ]);
  });

  test("una conferma riuscita lo stesso giorno sopprime il promemoria", async () => {
    const { deps, post } = setup({
      users: { u1: trialV2(1) },
      courses: { c1: courseDoc("c1") },
      [DEMO_LOG_COLLECTION]: {
        booked_u1_c1: { ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(SCHEDULED - 3600_000) },
      },
    });
    await expect(run(deps)).resolves.toMatchObject({ sent: 0, skipped: 1 });
    expect(post).not.toHaveBeenCalled();
  });

  test("conferma pending: il promemoria parte; promemoria pending: needs_review senza POST", async () => {
    const { deps, phonesPosted } = setup({
      users: { u1: trialV2(1), u2: trialV2(2) },
      courses: { c1: courseDoc("c1") },
      [DEMO_LOG_COLLECTION]: {
        booked_u1_c1: { ok: false, outcome: "pending", sentAt: Timestamp.fromMillis(SCHEDULED - 3600_000) },
        reminder_u2_c1: { ok: false, outcome: "pending", sentAt: Timestamp.fromMillis(SCHEDULED) },
      },
    });
    await expect(run(deps)).resolves.toMatchObject({ sent: 1, failed: 1 });
    expect(phonesPosted()).toEqual([`+39${phone(1)}`]);
  });

  test("HTTP 429 viene ritentato nel run; timeout e 5xx fanno una sola POST", async () => {
    const byPhone: Record<string, PostResult[]> = {
      [`+39${phone(1)}`]: [{ ok: false, status: 429 }, ok],
      [`+39${phone(2)}`]: [{ ok: false, status: 0 }],
      [`+39${phone(3)}`]: [{ ok: false, status: 502 }],
    };
    const post = jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(
      async (_u, _k, payload) => byPhone[payload.numero_di_telefono].shift() ?? ok
    );
    const { fake, deps, phonesPosted } = setup(
      { users: { u1: trialV2(1), u2: trialV2(2), u3: trialV2(3) }, courses: { c1: courseDoc("c1") } },
      { post }
    );
    await expect(run(deps)).resolves.toMatchObject({ sent: 1, failed: 2 });
    const counts = phonesPosted().reduce<Record<string, number>>((acc, p) => ({ ...acc, [p]: (acc[p] ?? 0) + 1 }), {});
    expect(counts).toEqual({ [`+39${phone(1)}`]: 2, [`+39${phone(2)}`]: 1, [`+39${phone(3)}`]: 1 });
    expect(fake.store[DEMO_LOG_COLLECTION]).toMatchObject({
      reminder_u1_c1: { outcome: "sent" },
      reminder_u2_c1: { outcome: "unknown" },
      reminder_u3_c1: { outcome: "unknown" },
    });
  });

  test("un errore Firestore prima della POST fa ritentare il job, che riprende solo quel promemoria", async () => {
    const store: Store = {
      users: { u1: trialV2(1), u2: trialV2(2) },
      courses: { c1: courseDoc("c1") },
    };
    const flaky = makeWhatsappDb(store, {
      createError: (key) => (key.endsWith("reminder_u2_c1") ? new Error("14 UNAVAILABLE") : undefined),
    });
    const first = setup(store);
    await expect(run({ ...first.deps, db: flaky.db })).rejects.toThrow(/ritentare/i);
    expect(first.phonesPosted()).toEqual([`+39${phone(1)}`]);

    const second = setup(store);
    await expect(run(second.deps)).resolves.toMatchObject({ sent: 1, skipped: 1, failed: 0 });
    expect(second.phonesPosted()).toEqual([`+39${phone(2)}`]);
  });

  test("un invio incerto non fa ritentare il job", async () => {
    const post = jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(async () => ({
      ok: false,
      status: 503,
    }));
    const { deps } = setup({ users: { u1: trialV2(1) }, courses: { c1: courseDoc("c1") } }, { post });
    await expect(run(deps)).resolves.toMatchObject({ sent: 0, failed: 1 });
  });

  test(`non tiene mai più di ${MAX_CONCURRENT_SENDS} POST contemporanee`, async () => {
    const users: Record<string, Data> = {};
    for (let i = 1; i <= 25; i++) users[`u${i}`] = trialV2(i);
    let inFlight = 0;
    let maxInFlight = 0;
    const release: Array<() => void> = [];
    const post = jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(
      () =>
        new Promise<PostResult>((resolve) => {
          inFlight++;
          maxInFlight = Math.max(maxInFlight, inFlight);
          release.push(() => {
            inFlight--;
            resolve(ok);
          });
        })
    );
    const { deps } = setup({ users, courses: { c1: courseDoc("c1") } }, { post });

    let finished = false;
    const done = run(deps).finally(() => {
      finished = true;
    });
    while (!finished) {
      await new Promise((resolve) => setImmediate(resolve));
      release.splice(0).forEach((fn) => fn());
    }
    await expect(done).resolves.toMatchObject({ sent: 25 });
    expect(maxInFlight).toBe(MAX_CONCURRENT_SENDS);
  });

  describe("deadline e ripresa del batch", () => {
    function bigStore(): Store {
      const users: Record<string, Data> = {};
      for (let i = 1; i <= 25; i++) users[`u${i}`] = trialV2(i);
      users.u99 = trialV2(99);
      return {
        users,
        courses: { c1: courseDoc("c1") },
        // Conferma partita il 14: deve restare soppressa anche nel retry.
        [DEMO_LOG_COLLECTION]: {
          booked_u99_c1: { ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(SCHEDULED - 3600_000) },
        },
      };
    }

    test.each([
      ["stessa sera", SCHEDULED + 600_000],
      ["dopo la mezzanotte di Roma", Date.UTC(2026, 9, 14, 22, 30)],
      ["dopo la mezzanotte UTC", Date.UTC(2026, 9, 15, 0, 30)],
    ])("un secondo run (%s) manda solo i promemoria rimasti", async (_label, retryNow) => {
      const store = bigStore();

      // Primo run: ogni POST fa avanzare l'orologio; la deadline scade a metà.
      let clock = 0;
      const post1 = jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(async () => {
        clock++;
        return ok;
      });
      const first = setup(store, { post: post1 });
      await expect(run(first.deps, { deadlineMillis: 12, now: () => clock })).rejects.toThrow(/deadline/i);
      const sentFirst = first.phonesPosted();
      expect(sentFirst.length).toBeGreaterThan(0);
      expect(sentFirst.length).toBeLessThan(25);
      // Il run fallisce solo dopo aver chiuso gli invii già avviati.
      const outcomes = Object.values(store[DEMO_LOG_COLLECTION]).map((d) => d.outcome);
      expect(outcomes.filter((o) => o === "pending")).toEqual([]);

      // Secondo run (retry di Cloud Scheduler): stesso scheduledAtMillis, stesso store.
      const second = setup(store, { nowMillis: retryNow });
      await expect(run(second.deps)).resolves.toMatchObject({
        sent: 25 - sentFirst.length,
        failed: 0,
      });
      const all = [...sentFirst, ...second.phonesPosted()];
      expect(all).toHaveLength(25);
      expect(new Set(all).size).toBe(25);
      expect(all).not.toContain(`+39${phone(99)}`);
    });
  });
});
