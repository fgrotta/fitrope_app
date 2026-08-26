import {
  deterministicSubscriptionId,
  subtractMonthsInRome,
  transformUser,
} from "../migration/userTransform";

const NOW = Date.parse("2026-08-26T10:00:00.000Z");
const END = Date.parse("2026-09-30T16:00:00.000Z"); // 18:00 Europe/Rome

function source(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    role: "User",
    tipologiaCorsoTags: ["Open"],
    tipologiaIscrizione: "ABBONAMENTO_MENSILE",
    entrateSettimanali: 2,
    fineIscrizione: END,
    ...extra,
  };
}

describe("user legacy migration matrix", () => {
  test.each([
    ["ABBONAMENTO_MENSILE", 1, 2, "open_2x_1m", "2026-09-26T10:00:00.000Z"],
    ["ABBONAMENTO_TRIMESTRALE", 3, 3, "open_3x_3m", "2026-11-26T11:00:00.000Z"],
    ["ABBONAMENTO_SEMESTRALE", 6, null, "open_unlim_6m", "2027-02-26T11:00:00.000Z"],
    ["ABBONAMENTO_ANNUALE", 12, 2, "open_2x_12m", "2027-08-26T10:00:00.000Z"],
  ])("converte %s", (legacy, months, weekly, planKey, endIso) => {
    const endMillis = Date.parse(endIso as string);
    const result = transformUser(
      "user-1",
      source({
        tipologiaIscrizione: legacy,
        entrateSettimanali: weekly,
        fineIscrizione: endMillis,
      }),
      NOW
    );
    expect(result.conversionStatus).toBe("CONVERTIBLE");
    expect(result.target).toMatchObject({
      id: deterministicSubscriptionId("user-1"),
      planKey,
      weeklyFrequency: weekly,
      endDateMillis: endMillis,
    });
    expect(result.target!.startDateMillis).toBe(
      subtractMonthsInRome(result.target!.endDateMillis, months)
    );
  });

  test.each([
    [{ tipologiaCorsoTags: ["Hey Mamma"] }, "HEY_MAMMA"],
    [{ role: "Trainer" }, "ROLE_NOT_USER"],
    [{ tipologiaIscrizione: "PACCHETTO_ENTRATE" }, "NO_EXACT_ENTRIES_PLAN"],
    [{ tipologiaIscrizione: "ABBONAMENTO_PROVA" }, "TRIAL_NOT_SUPPORTED"],
    [{ tipologiaIscrizione: "SCONOSCIUTA" }, "INVALID_LEGACY_TYPE"],
    [{ tipologiaCorsoTags: [] }, "INVALID_TAG_SHAPE"],
    [{ tipologiaCorsoTags: ["Open", "Personal Trainer"] }, "INVALID_TAG_SHAPE"],
    [{ entrateSettimanali: 4 }, "INVALID_WEEKLY_FREQUENCY"],
    [{ entrateSettimanali: undefined }, "INVALID_WEEKLY_FREQUENCY"],
    [{ fineIscrizione: null }, "MISSING_END_DATE"],
  ])("esclude con reason code %s", (change, reason) => {
    const result = transformUser("u", source(change), NOW);
    expect(result.conversionStatus).toBe("IGNORED");
    expect(result.reasonCode).toBe(reason);
  });

  test("esclude startDate nominale futura", () => {
    const result = transformUser(
      "u",
      source({ fineIscrizione: Date.parse("2026-12-01T17:00:00.000Z") }),
      NOW
    );
    expect(result.reasonCode).toBe("FUTURE_START");
  });
});

describe("sottrazione nominale Europe/Rome", () => {
  test("clampa la fine del mese e conserva l'ora locale attraversando DST", () => {
    const end = Date.parse("2026-03-31T16:00:00.000Z"); // 18:00 CEST
    const start = subtractMonthsInRome(end, 1);
    expect(new Date(start).toISOString()).toBe("2026-02-28T17:00:00.000Z"); // 18:00 CET
  });

  test("attraversa il ritorno all'ora solare", () => {
    const end = Date.parse("2026-11-30T17:00:00.000Z"); // 18:00 CET
    const start = subtractMonthsInRome(end, 1);
    expect(new Date(start).toISOString()).toBe("2026-10-30T17:00:00.000Z"); // 18:00 CET
  });
});
