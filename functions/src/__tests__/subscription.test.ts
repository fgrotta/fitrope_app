import { Timestamp } from "firebase-admin/firestore";
import {
  buildSubscriptionFromPlan,
  computeActiveSnapshot,
  findOverlapping,
  recordFromDoc,
  recordToSnapshotEntry,
  UserSubscriptionRecord,
  validateWindow,
} from "../enrollment/subscription";
import { planByKey } from "../enrollment/plansCatalog";

const DAY = 86400000;
const NOW = Date.UTC(2026, 8, 28, 10);

const base: UserSubscriptionRecord = {
  id: "s",
  planKey: "open_2x_1m",
  family: "OPEN",
  billingMode: "FREQUENCY",
  courseTypeTags: ["Open"],
  weeklyFrequency: 2,
  remainingEntries: null,
  startDateMillis: NOW - DAY,
  endDateMillis: NOW + DAY,
};

describe("computeActiveSnapshot", () => {
  test("tiene gli abbonamenti con inizio futuro", () => {
    const future = { ...base, id: "f", startDateMillis: NOW + 5 * DAY, endDateMillis: NOW + 30 * DAY };
    expect(computeActiveSnapshot([future], NOW).map((r) => r.id)).toEqual(["f"]);
  });

  test("esclude scaduti e revocati", () => {
    const expired = { ...base, id: "e", endDateMillis: NOW - 1 };
    const revoked = { ...base, id: "r", revokedAtMillis: NOW - DAY };
    const live = { ...base, id: "l" };
    expect(computeActiveSnapshot([expired, revoked, live], NOW).map((r) => r.id))
      .toEqual(["l"]);
  });
});

describe("findOverlapping", () => {
  const current = { ...base, id: "c", startDateMillis: NOW - 10 * DAY, endDateMillis: NOW + 10 * DAY };

  test("finestra sovrapposta della stessa famiglia", () => {
    expect(findOverlapping([current], "OPEN", NOW, NOW + 30 * DAY)).toHaveLength(1);
  });

  test("finestra successiva alla scadenza: nessun conflitto", () => {
    expect(findOverlapping([current], "OPEN", NOW + 10 * DAY + 1, NOW + 40 * DAY))
      .toHaveLength(0);
  });

  test("conflitto con un abbonamento futuro", () => {
    const future = { ...base, id: "f", startDateMillis: NOW + 20 * DAY, endDateMillis: NOW + 50 * DAY };
    expect(findOverlapping([future], "OPEN", NOW, NOW + 30 * DAY).map((r) => r.id))
      .toEqual(["f"]);
  });

  test("ignora revocati, altre famiglie e l'id escluso", () => {
    const revoked = { ...current, id: "r", revokedAtMillis: NOW };
    const pt = { ...current, id: "p", family: "PT" as const };
    expect(findOverlapping([revoked, pt, current], "OPEN", NOW, NOW + DAY, "c"))
      .toHaveLength(0);
  });
});

describe("validateWindow", () => {
  const start = Date.UTC(2026, 9, 1);
  test.each([
    ["NaN", NaN, start + DAY],
    ["fine NaN", start, NaN],
    ["non intero", start + 0.5, start + DAY],
    ["stringa", "2026-10-01", start + DAY],
    ["fine prima dell'inizio", start, start - DAY],
    ["fine uguale all'inizio", start, start],
    ["prima del 2020", Date.UTC(2019, 11, 31), start],
    ["dopo il 2100", start, Date.UTC(2100, 0, 2)],
  ])("%s -> invalid-argument", (_label, s, e) => {
    expect(() => validateWindow(s, e)).toThrow(
      expect.objectContaining({ code: "invalid-argument" }),
    );
  });

  test("finestra valida", () => {
    expect(() => validateWindow(start, start + DAY)).not.toThrow();
  });
});

describe("buildSubscriptionFromPlan", () => {
  test("fine personalizzata", () => {
    const plan = planByKey("open_2x_1m")!;
    const r = buildSubscriptionFromPlan(plan, NOW, NOW + 3 * DAY);
    expect(r.endDateMillis).toBe(NOW + 3 * DAY);
  });
});

describe("revokedAt", () => {
  const doc = {
    planKey: "open_2x_1m", family: "OPEN", billingMode: "FREQUENCY",
    courseTypeTags: ["Open"], weeklyFrequency: 2, remainingEntries: null,
    startDate: Timestamp.fromMillis(NOW - DAY), endDate: Timestamp.fromMillis(NOW + DAY),
  };

  test("recordFromDoc legge revokedAt; lo snapshot non lo contiene", () => {
    const r = recordFromDoc("x", { ...doc, revokedAt: Timestamp.fromMillis(NOW) });
    expect(r.revokedAtMillis).toBe(NOW);
    expect(recordToSnapshotEntry(r)).not.toHaveProperty("revokedAt");
    expect(recordToSnapshotEntry(r)).not.toHaveProperty("revokedAtMillis");
  });

  test("senza revokedAt il record non è revocato", () => {
    expect(recordFromDoc("x", doc).revokedAtMillis ?? null).toBeNull();
  });
});
