import { SubscriptionPlan, SubscriptionFamily, BillingMode } from "./plansCatalog";

// Record di abbonamento in millis (logica pura, indipendente da Firestore).
// Mappato su Dart UserSubscription (lib/types/userSubscription.dart).
export interface UserSubscriptionRecord {
  id?: string;
  planKey: string;
  family: SubscriptionFamily;
  billingMode: BillingMode;
  courseTypeTags: string[];
  weeklyFrequency: number | null;
  remainingEntries: number | null;
  startDateMillis: number;
  endDateMillis: number;
}

/**
 * Aggiunge [months] mesi a [startMillis] gestendo l'overflow di fine mese
 * (es. 31 gen + 1 mese = 28/29 feb).
 */
export function addMonths(startMillis: number, months: number): number {
  const d = new Date(startMillis);
  const day = d.getDate();
  d.setDate(1);
  d.setMonth(d.getMonth() + months);
  const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  d.setDate(Math.min(day, lastDay));
  return d.getTime();
}

/** Costruisce un abbonamento dal piano: la durata determina la finestra di validità. */
export function buildSubscriptionFromPlan(
  plan: SubscriptionPlan,
  startMillis: number
): UserSubscriptionRecord {
  return {
    planKey: plan.key,
    family: plan.family,
    billingMode: plan.billingMode,
    courseTypeTags: [...plan.grantedCourseTypeTags],
    weeklyFrequency: plan.weeklyFrequency,
    remainingEntries: plan.billingMode === "ENTRIES" ? plan.entries : null,
    startDateMillis: startMillis,
    endDateMillis: addMonths(startMillis, plan.durationMonths),
  };
}

/** Snapshot degli abbonamenti ancora attivi (non scaduti) alla data [nowMillis]. */
export function computeActiveSnapshot(
  records: UserSubscriptionRecord[],
  nowMillis: number
): UserSubscriptionRecord[] {
  return records.filter((r) => r.endDateMillis >= nowMillis);
}

/** True se per la famiglia esiste già un abbonamento attivo (vincolo: max 1 per famiglia). */
export function hasActiveForFamily(
  active: UserSubscriptionRecord[],
  family: SubscriptionFamily
): boolean {
  return active.some((r) => r.family === family);
}
