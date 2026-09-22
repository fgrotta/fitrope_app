import {
  canReconcileSubscriptionModel,
  hasLegacyEconomicState,
  hasLegacyEntryConsumption,
} from "../enrollment/provisioning";

describe("provisioning V2 guards", () => {
  test("uno stato legacy economico non e' promuovibile", () => {
    expect(hasLegacyEconomicState({ tipologiaIscrizione: "ABBONAMENTO_PROVA" })).toBe(true);
    expect(hasLegacyEconomicState({ entrateDisponibili: 1 })).toBe(true);
  });

  test("un consumo LEGACY_ENTRY blocca il cutover", () => {
    expect(hasLegacyEntryConsumption({
      enrollmentConsumption: { c1: { kind: "LEGACY_ENTRY" } },
    })).toBe(true);
    expect(canReconcileSubscriptionModel({
      activeSubscriptions: [{}], enrollmentConsumption: { c1: { kind: "LEGACY_ENTRY" } },
    }, [{}])).toBe(false);
  });

  test("solo un V2 puro con subscription e' riconciliabile", () => {
    expect(canReconcileSubscriptionModel({ activeSubscriptions: [{}] }, [{}])).toBe(true);
    expect(canReconcileSubscriptionModel({ activeSubscriptions: [{}], fineIscrizione: 1 }, [{}])).toBe(false);
  });
});
