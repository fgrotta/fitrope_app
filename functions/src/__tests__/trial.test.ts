import { isTrialUser, TRIAL_PLAN_KEY } from "../enrollment/trial";
import { planByKey } from "../enrollment/plansCatalog";
import { UserSubscriptionRecord } from "../enrollment/subscription";

function record(planKey: string): UserSubscriptionRecord {
  return {
    id: planKey,
    planKey,
    family: "OPEN",
    billingMode: "ENTRIES",
    courseTypeTags: ["Open"],
    weeklyFrequency: null,
    remainingEntries: 1,
    startDateMillis: 0,
    endDateMillis: Number.MAX_SAFE_INTEGER,
  };
}

describe("isTrialUser", () => {
  test("TRIAL_PLAN_KEY esiste nel catalogo piani (guardia contro il drift)", () => {
    expect(planByKey(TRIAL_PLAN_KEY)).toBeDefined();
  });

  test("modello V2: abbonamento vivo sul piano di prova", () => {
    expect(isTrialUser({ subscriptionModelVersion: 2 }, [record(TRIAL_PLAN_KEY)])).toBe(true);
  });

  test("convertito al multi-abbonamento con tipologia legacy PROVA: NON è di prova", () => {
    expect(
      isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA" }, [record("open_2x_3m")])
    ).toBe(false);
  });

  test("legacy PROVA senza abbonamenti vivi e senza versione: è di prova", () => {
    expect(isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA" }, [])).toBe(true);
  });

  test("legacy PROVA ma già sul modello V2: NON è di prova", () => {
    expect(
      isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA", subscriptionModelVersion: 2 }, [])
    ).toBe(false);
  });

  test("legacy non PROVA: NON è di prova", () => {
    expect(isTrialUser({ tipologiaIscrizione: "PACCHETTO_ENTRATE" }, [])).toBe(false);
  });
});
