import { Timestamp } from "firebase-admin/firestore";
import {
  DEMO_LOG_COLLECTION,
  claimSend,
  demoLogDocId,
  markSendOutcome,
  wasNotifiedToday,
} from "../whatsapp/sendLog";
import { makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

// 14 ottobre 2026, 19:00 ora di Roma (CEST).
const NOW = Date.UTC(2026, 9, 14, 17);
const KEY = "booked_u1_c1";

function logDoc(fake: ReturnType<typeof makeWhatsappDb>, id = KEY) {
  return fake.store[DEMO_LOG_COLLECTION]?.[id];
}

afterEach(() => jest.clearAllMocks());

describe("demoLogDocId", () => {
  test("usa kind_userId_courseId, come il branch di riferimento", () => {
    expect(demoLogDocId("booked", "u1", "c1")).toBe("booked_u1_c1");
    expect(demoLogDocId("reminder", "u1", "c1")).toBe("reminder_u1_c1");
  });

  test("rifiuta id che non sarebbero un documento valido", () => {
    expect(() => demoLogDocId("booked", "", "c1")).toThrow();
    expect(() => demoLogDocId("booked", "u/1", "c1")).toThrow();
  });
});

describe("claimSend", () => {
  test("crea il claim in modo atomico, pending e senza dati personali", async () => {
    const fake = makeWhatsappDb();
    await expect(claimSend(fake.db, "booked", "u1", "c1", NOW)).resolves.toBe("claimed");
    expect(fake.ops).toEqual([`create ${DEMO_LOG_COLLECTION}/${KEY}`]);
    const doc = logDoc(fake)!;
    expect(Object.keys(doc).sort()).toEqual(["courseId", "kind", "ok", "outcome", "sentAt", "userId"]);
    expect(doc).toMatchObject({ kind: "booked", userId: "u1", courseId: "c1", ok: false, outcome: "pending" });
    expect((doc.sentAt as Timestamp).toMillis()).toBe(NOW);
  });

  test("secondo claim su un invio riuscito → sent", async () => {
    const fake = makeWhatsappDb();
    await claimSend(fake.db, "booked", "u1", "c1", NOW);
    await markSendOutcome(fake.db, "booked", "u1", "c1", "sent", 200);
    await expect(claimSend(fake.db, "booked", "u1", "c1", NOW + 1000)).resolves.toBe("sent");
  });

  test.each([
    ["pending (interruzione dopo il claim)", { ok: false, outcome: "pending" }],
    ["unknown", { ok: false, outcome: "unknown" }],
    ["rejected", { ok: false, outcome: "rejected", status: 410 }],
    ["legacy senza ok", { kind: "booked", userId: "u1", courseId: "c1" }],
  ])("secondo claim su %s → needs_review, senza toccare il documento", async (_label, existing) => {
    const fake = makeWhatsappDb({ [DEMO_LOG_COLLECTION]: { [KEY]: { ...existing } } });
    await expect(claimSend(fake.db, "booked", "u1", "c1", NOW)).resolves.toBe("needs_review");
    expect(logDoc(fake)).toEqual(existing);
    expect(fake.ops.filter((op) => op.startsWith("update"))).toEqual([]);
  });

  test("un errore Firestore diverso da ALREADY_EXISTS viene rilanciato", async () => {
    const fake = makeWhatsappDb({}, { createError: () => new Error("7 PERMISSION_DENIED") });
    await expect(claimSend(fake.db, "booked", "u1", "c1", NOW)).rejects.toThrow(/PERMISSION_DENIED/);
  });

  test("ALREADY_EXISTS riconosciuto anche dal solo messaggio", async () => {
    const fake = makeWhatsappDb(
      { [DEMO_LOG_COLLECTION]: { [KEY]: { ok: true, outcome: "sent" } } },
      { createError: () => new Error("6 ALREADY_EXISTS: entity already exists") }
    );
    await expect(claimSend(fake.db, "booked", "u1", "c1", NOW)).resolves.toBe("sent");
  });
});

describe("markSendOutcome", () => {
  test.each([
    ["sent", 200, true],
    ["rejected", 410, false],
    ["unknown", 503, false],
  ] as const)("%s → ok %s, con lo status HTTP", async (outcome, status, ok) => {
    const fake = makeWhatsappDb();
    await claimSend(fake.db, "booked", "u1", "c1", NOW);
    await markSendOutcome(fake.db, "booked", "u1", "c1", outcome, status);
    expect(logDoc(fake)).toMatchObject({ outcome, ok, status });
  });

  test("senza risposta HTTP non registra uno status", async () => {
    const fake = makeWhatsappDb();
    await claimSend(fake.db, "booked", "u1", "c1", NOW);
    await markSendOutcome(fake.db, "booked", "u1", "c1", "unknown", 0);
    expect(logDoc(fake)).toMatchObject({ outcome: "unknown", ok: false });
    expect(logDoc(fake)).not.toHaveProperty("status");
  });

  test("non cancella mai il claim, nemmeno su un invio incerto", async () => {
    const fake = makeWhatsappDb();
    await claimSend(fake.db, "booked", "u1", "c1", NOW);
    await markSendOutcome(fake.db, "booked", "u1", "c1", "unknown");
    expect(logDoc(fake)).toBeDefined();
    expect(fake.ops.some((op) => op.startsWith("delete"))).toBe(false);
  });

  test("un errore di update viene rilanciato: il chiamante lascia il claim pending", async () => {
    const fake = makeWhatsappDb({}, { updateError: () => new Error("14 UNAVAILABLE") });
    await claimSend(fake.db, "booked", "u1", "c1", NOW);
    await expect(markSendOutcome(fake.db, "booked", "u1", "c1", "sent", 200)).rejects.toThrow(
      /UNAVAILABLE/
    );
    expect(logDoc(fake)).toMatchObject({ outcome: "pending", ok: false });
  });
});

describe("wasNotifiedToday", () => {
  const booked = (over: Record<string, unknown>) =>
    makeWhatsappDb({
      [DEMO_LOG_COLLECTION]: {
        [KEY]: { kind: "booked", userId: "u1", courseId: "c1", ...over },
      },
    });

  test("vero con una conferma riuscita nello stesso giorno di Roma", async () => {
    const fake = booked({ ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(Date.UTC(2026, 9, 14, 8)) });
    await expect(wasNotifiedToday(fake.db, "u1", "c1", NOW)).resolves.toBe(true);
  });

  test("falso senza documento", async () => {
    await expect(wasNotifiedToday(makeWhatsappDb().db, "u1", "c1", NOW)).resolves.toBe(false);
  });

  test("falso a cavallo della mezzanotte di Roma", async () => {
    // 21:30 UTC del 13 = 23:30 del 13 a Roma: il giorno prima di NOW.
    const fake = booked({ ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(Date.UTC(2026, 9, 13, 21, 30)) });
    await expect(wasNotifiedToday(fake.db, "u1", "c1", NOW)).resolves.toBe(false);
    // 22:30 UTC del 13 = 00:30 del 14 a Roma: stesso giorno di NOW.
    const later = booked({ ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(Date.UTC(2026, 9, 13, 22, 30)) });
    await expect(wasNotifiedToday(later.db, "u1", "c1", NOW)).resolves.toBe(true);
  });

  test.each([
    ["pending", { ok: false, outcome: "pending" }],
    ["unknown", { ok: false, outcome: "unknown" }],
    ["rejected", { ok: false, outcome: "rejected" }],
    ["legacy senza ok", {}],
  ])("una conferma %s non sopprime il promemoria", async (_label, over) => {
    const fake = booked({ ...over, sentAt: Timestamp.fromMillis(NOW - 3600_000) });
    await expect(wasNotifiedToday(fake.db, "u1", "c1", NOW)).resolves.toBe(false);
  });

  test("legge solo il documento della conferma", async () => {
    const fake = makeWhatsappDb({
      [DEMO_LOG_COLLECTION]: {
        reminder_u1_c1: { ok: true, outcome: "sent", sentAt: Timestamp.fromMillis(NOW) },
      },
    });
    await expect(wasNotifiedToday(fake.db, "u1", "c1", NOW)).resolves.toBe(false);
    expect(fake.ops).toEqual([`get ${DEMO_LOG_COLLECTION}/${KEY}`]);
  });
});
