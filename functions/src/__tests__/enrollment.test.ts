import {
  SUBSCRIPTION_PLANS,
  planByKey,
} from "../enrollment/plansCatalog";
import {
  addMonths,
  buildSubscriptionFromPlan,
  computeActiveSnapshot,
  hasActiveForFamily,
  UserSubscriptionRecord,
} from "../enrollment/subscription";

describe("Catalogo piani (mirror Dart)", () => {
  test("20 piani: 12 Open + 4 Hyrox + 4 PT, chiavi univoche", () => {
    expect(SUBSCRIPTION_PLANS.length).toBe(20);
    expect(SUBSCRIPTION_PLANS.filter((p) => p.family === "OPEN").length).toBe(12);
    expect(SUBSCRIPTION_PLANS.filter((p) => p.family === "HYROX").length).toBe(4);
    expect(SUBSCRIPTION_PLANS.filter((p) => p.family === "PT").length).toBe(4);
    const keys = SUBSCRIPTION_PLANS.map((p) => p.key);
    expect(new Set(keys).size).toBe(keys.length);
  });

  test("chiavi attese presenti (allineamento col client Dart)", () => {
    for (const key of [
      "open_2x_1m",
      "open_3x_3m",
      "open_unlim_12m",
      "hyrox_10i_1m",
      "pt_10i_6m",
    ]) {
      expect(planByKey(key)).toBeDefined();
    }
    expect(planByKey("inesistente")).toBeUndefined();
  });

  test("Open ha frequenze {2,3,null}; Hyrox/PT 10 ingressi ENTRIES", () => {
    const open1m = SUBSCRIPTION_PLANS.filter(
      (p) => p.family === "OPEN" && p.durationMonths === 1
    );
    expect(new Set(open1m.map((p) => p.weeklyFrequency))).toEqual(
      new Set([2, 3, null])
    );
    expect(
      SUBSCRIPTION_PLANS.filter((p) => p.family !== "OPEN").every(
        (p) => p.billingMode === "ENTRIES" && p.entries === 10
      )
    ).toBe(true);
  });
});

describe("addMonths", () => {
  test("avanza di N mesi conservando il giorno", () => {
    const r = new Date(addMonths(new Date(2026, 0, 15).getTime(), 3));
    expect(r.getMonth()).toBe(3); // aprile
    expect(r.getDate()).toBe(15);
  });

  test("gestisce overflow fine mese (31 gen + 1 mese -> 28 feb 2026)", () => {
    const r = new Date(addMonths(new Date(2026, 0, 31).getTime(), 1));
    expect(r.getMonth()).toBe(1); // febbraio, non marzo
    expect(r.getDate()).toBe(28); // 2026 non bisestile
  });
});

describe("buildSubscriptionFromPlan", () => {
  const start = new Date(2026, 0, 1).getTime();

  test("FREQUENCY: weeklyFrequency impostata, remainingEntries null", () => {
    const r = buildSubscriptionFromPlan(planByKey("open_2x_3m")!, start);
    expect(r.weeklyFrequency).toBe(2);
    expect(r.remainingEntries).toBeNull();
    expect(r.courseTypeTags).toEqual(["Open"]);
    expect(new Date(r.endDateMillis).getMonth()).toBe(3); // +3 mesi
  });

  test("ENTRIES: remainingEntries = 10, weeklyFrequency null", () => {
    const r = buildSubscriptionFromPlan(planByKey("hyrox_10i_1m")!, start);
    expect(r.billingMode).toBe("ENTRIES");
    expect(r.remainingEntries).toBe(10);
    expect(r.weeklyFrequency).toBeNull();
    expect(r.family).toBe("HYROX");
  });
});

describe("snapshot", () => {
  const base: UserSubscriptionRecord = {
    planKey: "open_2x_1m",
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency: 2,
    remainingEntries: null,
    startDateMillis: 0,
    endDateMillis: 0,
  };

  test("computeActiveSnapshot scarta gli scaduti", () => {
    const recs = [
      { ...base, endDateMillis: 500 },
      { ...base, endDateMillis: 2000 },
    ];
    const active = computeActiveSnapshot(recs, 1000);
    expect(active.length).toBe(1);
    expect(active[0].endDateMillis).toBe(2000);
  });

  test("hasActiveForFamily", () => {
    const active = [{ ...base, family: "OPEN" as const, endDateMillis: 2000 }];
    expect(hasActiveForFamily(active, "OPEN")).toBe(true);
    expect(hasActiveForFamily(active, "HYROX")).toBe(false);
  });
});
