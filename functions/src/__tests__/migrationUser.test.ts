import {
  deterministicSubscriptionId,
  subtractMonthsInRome,
  transformUser,
  userNormalization,
} from "../migration/userTransform";

const NOW = Date.parse("2026-08-26T10:00:00.000Z");
const END = Date.parse("2026-09-30T16:00:00.000Z"); // 18:00 Europe/Rome

function source(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    role: "User",
    tipologiaCorsoTags: ["Open"],
    tipologiaIscrizione: "ABBONAMENTO_MENSILE",
    entrateDisponibili: null,
    entrateSettimanali: 2,
    fineIscrizione: END,
    ...extra,
  };
}

describe("user legacy migration matrix", () => {
  test.each([
    [{ role: undefined }, { role: "User" }],
    [{ role: null }, { role: "User" }],
    [{ role: "" }, { role: "User" }],
    [{ tipologiaCorsoTags: null }, { tipologiaCorsoTags: ["Open"] }],
    [{ tipologiaCorsoTags: [], role: "User" }, { tipologiaCorsoTags: ["Open"] }],
  ])("applica i default condivisi a %s", (change, expected) => {
    expect(userNormalization(source(change)).fields).toEqual(expected);
  });

  test("preserva ruolo esplicito e tag ambigui", () => {
    expect(userNormalization(source({ role: "Admin" })).fields).toEqual({});
    expect(userNormalization(source({ role: "Trainer" })).fields).toEqual({});
    expect(userNormalization(source({ role: 7 })).fields).toEqual({});
    expect(userNormalization(source({ tipologiaCorsoTags: "Open" })).fields).toEqual({});
    expect(userNormalization(source({
      tipologiaCorsoTags: ["Open", "Personal Trainer"],
    })).fields).toEqual({});
  });

  test("normalizza i tag solo per piani legacy riconosciuti", () => {
    expect(userNormalization(source({
      tipologiaIscrizione: "SCONOSCIUTA",
      tipologiaCorsoTags: [],
    })).fields).toEqual({});
  });

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
    [{ tipologiaIscrizione: "SCONOSCIUTA" }, "INVALID_LEGACY_TYPE"],
    [{ tipologiaCorsoTags: [] }, "FUTURE_START"],
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

  test.each([
    ["ABBONAMENTO_PROVA", ["Open"], 1, "open_trial_1i_30d", "OPEN"],
    ["PACCHETTO_ENTRATE", ["Open"], 7, "open_10i_3m", "OPEN"],
    ["PACCHETTO_ENTRATE", ["Personal Trainer"], 4, "pt_10i_3m", "PT"],
  ])("converte il legacy a ingressi %s/%s", (legacy, tags, entries, planKey, family) => {
    const end = legacy === "ABBONAMENTO_PROVA"
      ? NOW + 10 * 86400000
      : Date.parse("2026-09-30T16:00:00.000Z");
    const result = transformUser("entry-user", source({
      tipologiaIscrizione: legacy,
      tipologiaCorsoTags: tags,
      entrateDisponibili: entries,
      fineIscrizione: end,
    }), NOW);
    expect(result).toMatchObject({
      conversionStatus: "CONVERTIBLE",
      target: {
        planKey,
        family,
        billingMode: "ENTRIES",
        remainingEntries: entries,
        endDateMillis: end,
      },
    });
  });

  test.each([
    [-1, "INVALID_ENTRY_BALANCE"],
    [11, "ENTRY_BALANCE_EXCEEDS_PLAN"],
  ])("esclude saldo pacchetto %s", (entries, reason) => {
    const result = transformUser("u", source({
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: entries,
    }), NOW);
    expect(result.reasonCode).toBe(reason);
  });

  test("esclude una prenotazione futura non coperta", () => {
    const result = transformUser("u", source({
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 5,
    }), NOW, [{
      courseId: "pt-future",
      startDateMillis: NOW + 86400000,
      courseTypeTag: "Personal Trainer",
    }]);
    expect(result.reasonCode).toBe("FUTURE_BOOKING_NOT_COVERED");
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
