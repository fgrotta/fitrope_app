import { FieldValue } from "firebase-admin/firestore";

export type LegacyMigrationSource =
  | "BATCH"
  | "ADMIN_AUTO"
  | "ADMIN_GUIDED"
  // Prova V1 chiusa da assignSubscription: nessuna conversione, solo pulizia.
  | "ADMIN_TRIAL_REPLACED";

export function legacySubscriptionMigrationMarker(
  source: LegacyMigrationSource,
  subscriptionId: string,
  planKey: string,
  actor: string,
): Record<string, unknown> {
  return {
    version: 2,
    source,
    subscriptionId,
    planKey,
    migratedAt: FieldValue.serverTimestamp(),
    actor,
  };
}
