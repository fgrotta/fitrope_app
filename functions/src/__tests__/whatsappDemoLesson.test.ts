import { Timestamp } from "firebase-admin/firestore";
import {
  DemoCourse,
  DemoUser,
  WhatsappDeps,
  checkRecipient,
  dispatchDemoLesson,
  mapDemoCourseDoc,
  mapDemoUserDoc,
  notifyDemoLessonBooked,
} from "../whatsapp/demoLesson";
import { DEMO_LOG_COLLECTION } from "../whatsapp/sendLog";
import { PostResult } from "../whatsapp/makeClient";
import { DemoLessonPayload } from "../whatsapp/payload";
import { Data, Store, WhatsappFakeDbOptions, makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const API_KEY = "chiave-super-segreta";
// 14 ottobre 2026, 19:00 ora di Roma; la lezione è domani alle 18:00.
const NOW = Date.UTC(2026, 9, 14, 17);
const DOMANI_18 = Date.UTC(2026, 9, 15, 16);

const userDoc = (over: Data = {}): Data => ({
  uid: "u1",
  name: "Mario",
  lastName: "Rossi",
  numeroTelefono: "3331234567",
  isActive: true,
  courses: ["c1"],
  ...over,
});

const courseDoc = (over: Data = {}): Data => ({
  uid: "c1",
  name: "Corso Excel Avanzato",
  startDate: Timestamp.fromMillis(DOMANI_18),
  reminderEnabled: true,
  ...over,
});

const user = (over: Data = {}): DemoUser => mapDemoUserDoc({ id: "u1", data: () => userDoc(over) });
const course = (over: Data = {}): DemoCourse =>
  mapDemoCourseDoc({ id: "c1", data: () => courseDoc(over) });

const ok = (status = 200): PostResult => ({ ok: true, status });
const ko = (status: number): PostResult => ({ ok: false, status });

function setup(
  opts: {
    store?: Store;
    responses?: Array<PostResult | Error>;
    env?: NodeJS.ProcessEnv;
    db?: WhatsappFakeDbOptions;
  } = {}
) {
  const fake = makeWhatsappDb(
    opts.store ?? { users: { u1: userDoc() }, courses: { c1: courseDoc() } },
    opts.db
  );
  const queue = [...(opts.responses ?? [ok()])];
  const post = jest.fn<Promise<PostResult>, [string, string, DemoLessonPayload]>(async () => {
    const next = queue.length > 1 ? queue.shift()! : queue[0];
    if (next instanceof Error) throw next;
    return next;
  });
  const wait = jest.fn<Promise<void>, [number]>(async () => undefined);
  const deps: WhatsappDeps = {
    db: fake.db,
    webhookUrl: WEBHOOK_URL,
    apiKey: API_KEY,
    post,
    nowMillis: NOW,
    env: opts.env ?? {},
    wait,
  };
  const log = (id: string) => fake.store[DEMO_LOG_COLLECTION]?.[id];
  const creates = () => fake.ops.filter((op) => op.startsWith("create"));
  return { fake, deps, post, wait, log, creates };
}

function allLoggedText(): string {
  const { logger } = jest.requireMock("firebase-functions");
  return ["info", "warn", "error"]
    .flatMap((level) => (logger[level] as jest.Mock).mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

afterEach(() => jest.clearAllMocks());

describe("mapDemoCourseDoc", () => {
  test("usa uid, docId e la data del corso", () => {
    expect(mapDemoCourseDoc({ id: "doc-1", data: () => courseDoc({ uid: "c9" }) })).toEqual({
      uid: "c9",
      docId: "doc-1",
      name: "Corso Excel Avanzato",
      startAtMillis: DOMANI_18,
      reminderEnabled: true,
    });
  });

  test("ricade su id e poi su doc.id per i documenti storici senza uid", () => {
    expect(mapDemoCourseDoc({ id: "d2", data: () => ({ id: "c-legacy" }) }).uid).toBe("c-legacy");
    expect(mapDemoCourseDoc({ id: "d3", data: () => ({}) }).uid).toBe("d3");
  });

  test("un corso senza data ha startAtMillis null", () => {
    expect(mapDemoCourseDoc({ id: "d", data: () => ({ name: "X" }) }).startAtMillis).toBeNull();
  });
});

describe("mapDemoUserDoc", () => {
  test("applica i default e ricade sull'id del documento", () => {
    expect(mapDemoUserDoc({ id: "u9", data: () => ({ name: "Test" }) })).toEqual({
      uid: "u9",
      name: "Test",
      lastName: "",
      numeroTelefono: null,
      isActive: true,
      courses: [],
    });
  });
});

describe("checkRecipient", () => {
  test("accetta un utente attivo con un cellulare valido", () => {
    expect(checkRecipient("reminder", user(), course(), NOW, {})).toEqual({
      ok: true,
      nome: "Mario Rossi",
      corso: "Corso Excel Avanzato",
      phoneE164: "+393331234567",
      startAtMillis: DOMANI_18,
    });
  });

  test.each([
    ["inactive", { isActive: false }],
    ["no_phone", { numeroTelefono: null }],
    ["no_phone", { numeroTelefono: "-" }],
    ["not_mobile", { numeroTelefono: "0392123456" }],
    ["not_numeric", { numeroTelefono: "n/d" }],
    ["no_name", { name: "", lastName: " " }],
  ])("scarta l'utente con reason %s", (reason, over) => {
    expect(checkRecipient("booked", user(over), course(), NOW, {})).toEqual({ ok: false, reason });
  });

  test.each([
    ["course_without_date", { startDate: null }],
    ["course_in_past", { startDate: Timestamp.fromMillis(NOW - 1) }],
    ["course_in_past", { startDate: Timestamp.fromMillis(NOW) }],
    ["no_course_name", { name: "   " }],
  ])("scarta il corso con reason %s", (reason, over) => {
    expect(checkRecipient("booked", user(), course(over), NOW, {})).toEqual({ ok: false, reason });
  });

  test("reminderEnabled:false blocca il promemoria ma non la conferma", () => {
    const noReminder = course({ reminderEnabled: false });
    expect(checkRecipient("reminder", user(), noReminder, NOW, {})).toEqual({
      ok: false,
      reason: "reminder_disabled",
    });
    expect(checkRecipient("booked", user(), noReminder, NOW, {})).toMatchObject({ ok: true });
  });

  test("su staging scarta i numeri fuori allowlist", () => {
    expect(checkRecipient("booked", user(), course(), NOW, { APP_ENV: "staging" })).toEqual({
      ok: false,
      reason: "not_in_staging_allowlist",
    });
    expect(
      checkRecipient("booked", user(), course(), NOW, {
        APP_ENV: "staging",
        STAGING_WHATSAPP_ALLOWLIST: "3331234567",
      })
    ).toMatchObject({ ok: true });
  });
});

describe("dispatchDemoLesson", () => {
  test("un invio riuscito: una POST col body di conferma e claim sent", async () => {
    const { deps, post, log, creates } = setup();
    await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0]).toEqual([
      WEBHOOK_URL,
      API_KEY,
      {
        tipo: "conferma",
        nome: "Mario Rossi",
        numero_di_telefono: "+393331234567",
        corso: "Corso Excel Avanzato",
        giorno: "15 ottobre 2026",
        orario: "18:00",
      },
    ]);
    expect(creates()).toEqual([`create ${DEMO_LOG_COLLECTION}/booked_u1_c1`]);
    expect(log("booked_u1_c1")).toMatchObject({ ok: true, outcome: "sent", status: 200 });
  });

  test("uno scarto a monte non crea claim e non chiama Make", async () => {
    const { deps, post, creates } = setup();
    await expect(
      dispatchDemoLesson(deps, "booked", user({ numeroTelefono: null }), course())
    ).resolves.toEqual({ sent: false, reason: "no_phone" });
    expect(post).not.toHaveBeenCalled();
    expect(creates()).toEqual([]);
  });

  test("429, 429, 200: tre POST sotto un solo claim, con attese 250 e 1000 ms", async () => {
    const { deps, post, wait, log, creates } = setup({ responses: [ko(429), ko(429), ok()] });
    await expect(dispatchDemoLesson(deps, "reminder", user(), course())).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(3);
    expect(wait.mock.calls).toEqual([[250], [1000]]);
    expect(creates()).toHaveLength(1);
    expect(log("reminder_u1_c1")).toMatchObject({ ok: true, outcome: "sent" });
  });

  test("tre 429: rejected dopo due nuovi tentativi", async () => {
    const { deps, post, log } = setup({ responses: [ko(429)] });
    await expect(dispatchDemoLesson(deps, "reminder", user(), course())).resolves.toMatchObject({
      sent: false,
      failed: true,
    });
    expect(post).toHaveBeenCalledTimes(3);
    expect(log("reminder_u1_c1")).toMatchObject({ ok: false, outcome: "rejected", status: 429 });
  });

  test("410: una sola POST e rejected", async () => {
    const { deps, post, wait, log } = setup({ responses: [ko(410)] });
    await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toMatchObject({
      sent: false,
      failed: true,
    });
    expect(post).toHaveBeenCalledTimes(1);
    expect(wait).not.toHaveBeenCalled();
    expect(log("booked_u1_c1")).toMatchObject({ ok: false, outcome: "rejected", status: 410 });
  });

  test.each([
    ["timeout / status 0", ko(0)],
    ["HTTP 503", ko(503)],
    ["eccezione della post", new Error("socket hang up")],
  ])("%s: una sola POST e unknown, senza lanciare", async (_label, response) => {
    const { deps, post, log } = setup({ responses: [response] });
    await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toMatchObject({
      sent: false,
      failed: true,
    });
    expect(post).toHaveBeenCalledTimes(1);
    expect(log("booked_u1_c1")).toMatchObject({ ok: false, outcome: "unknown" });
  });

  test("secondo tentativo su un invio riuscito: nessuna POST", async () => {
    const { deps, post } = setup();
    await dispatchDemoLesson(deps, "booked", user(), course());
    await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toEqual({
      sent: false,
      reason: "already_sent",
    });
    expect(post).toHaveBeenCalledTimes(1);
  });

  test.each(["pending", "unknown", "rejected"])(
    "secondo tentativo su un claim %s: needs_review senza POST",
    async (outcome) => {
      const { deps, post } = setup({
        store: {
          users: { u1: userDoc() },
          courses: { c1: courseDoc() },
          [DEMO_LOG_COLLECTION]: { booked_u1_c1: { ok: false, outcome } },
        },
      });
      await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toEqual({
        sent: false,
        failed: true,
        reason: "needs_review",
      });
      expect(post).not.toHaveBeenCalled();
    }
  );

  test("esito non scrivibile dopo un 2xx: niente seconda POST, claim pending da verificare", async () => {
    const { deps, post, log } = setup({
      db: { updateError: () => new Error("14 UNAVAILABLE") },
    });
    await expect(dispatchDemoLesson(deps, "booked", user(), course())).resolves.toEqual({
      sent: false,
      failed: true,
      reason: "needs_review",
    });
    expect(post).toHaveBeenCalledTimes(1);
    expect(log("booked_u1_c1")).toMatchObject({ ok: false, outcome: "pending" });
  });

  test("promemoria soppresso da una conferma riuscita nello stesso giorno", async () => {
    const { deps, post } = setup({
      store: {
        [DEMO_LOG_COLLECTION]: {
          booked_u1_c1: { ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(NOW - 3600_000) },
        },
      },
    });
    await expect(dispatchDemoLesson(deps, "reminder", user(), course())).resolves.toEqual({
      sent: false,
      reason: "already_notified_today",
    });
    expect(post).not.toHaveBeenCalled();
  });

  test("una conferma pending non sopprime il promemoria", async () => {
    const { deps, post } = setup({
      store: {
        [DEMO_LOG_COLLECTION]: {
          booked_u1_c1: { ok: false, outcome: "pending", sentAt: Timestamp.fromMillis(NOW - 3600_000) },
        },
      },
    });
    await expect(dispatchDemoLesson(deps, "reminder", user(), course())).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(1);
  });

  test("il giorno della soppressione è noticeDayMillis, non l'ora corrente", async () => {
    // Conferma partita il 14; il retry del cron gira dopo mezzanotte, ma per il 14.
    const { deps, post } = setup({
      store: {
        [DEMO_LOG_COLLECTION]: {
          booked_u1_c1: { ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(NOW - 3600_000) },
        },
      },
    });
    const afterMidnight = { ...deps, nowMillis: Date.UTC(2026, 9, 14, 22, 30) };
    await expect(
      dispatchDemoLesson(afterMidnight, "reminder", user(), course(), NOW)
    ).resolves.toEqual({ sent: false, reason: "already_notified_today" });
    expect(post).not.toHaveBeenCalled();
  });

  test("i log non contengono numero, URL, chiave né payload", async () => {
    const { deps } = setup({ responses: [ko(503)] });
    await dispatchDemoLesson(deps, "booked", user(), course());
    const { deps: deps2 } = setup({ responses: [new Error(`boom ${WEBHOOK_URL} ${API_KEY}`)] });
    await dispatchDemoLesson(deps2, "booked", user(), course());
    const logged = allLoggedText();
    for (const secret of [WEBHOOK_URL, API_KEY, "3331234567", "Mario Rossi", "Corso Excel"]) {
      expect(logged).not.toContain(secret);
    }
  });
});

describe("notifyDemoLessonBooked", () => {
  test("legge utente e corso da Firestore e manda la conferma", async () => {
    const { deps, post } = setup();
    await expect(notifyDemoLessonBooked(deps, "u1", "c1")).resolves.toEqual({ sent: true });
    expect(post.mock.calls[0][2]).toMatchObject({ tipo: "conferma", corso: "Corso Excel Avanzato" });
  });

  test("trova il corso per uid quando l'id del documento è diverso", async () => {
    const { deps, post, log } = setup({
      store: { users: { u1: userDoc() }, courses: { "doc-storico": courseDoc({ uid: "c1" }) } },
    });
    await expect(notifyDemoLessonBooked(deps, "u1", "c1")).resolves.toEqual({ sent: true });
    expect(post).toHaveBeenCalledTimes(1);
    expect(log("booked_u1_c1")).toMatchObject({ ok: true });
  });

  test("utente o corso mancanti: nessun invio", async () => {
    const { deps, post } = setup({ store: { users: {}, courses: { c1: courseDoc() } } });
    await expect(notifyDemoLessonBooked(deps, "u1", "c1")).resolves.toEqual({
      sent: false,
      reason: "user_not_found",
    });
    const second = setup({ store: { users: { u1: userDoc() }, courses: {} } });
    await expect(notifyDemoLessonBooked(second.deps, "u1", "c1")).resolves.toEqual({
      sent: false,
      reason: "course_not_found",
    });
    expect(post).not.toHaveBeenCalled();
    expect(second.post).not.toHaveBeenCalled();
  });

  test("uno scarto viene registrato nei log col motivo", async () => {
    const { deps } = setup({ store: { users: { u1: userDoc({ isActive: false }) }, courses: { c1: courseDoc() } } });
    await expect(notifyDemoLessonBooked(deps, "u1", "c1")).resolves.toEqual({
      sent: false,
      reason: "inactive",
    });
    expect(allLoggedText()).toContain("inactive");
  });
});
