import { FieldValue } from "firebase-admin/firestore";

export type LegacyMigrationSource = "BATCH" | "ADMIN_AUTO" | "ADMIN_GUIDED";

export function legacySubscriptionMigrationMarker(
  source: LegacyMigrationSource,
  subscriptionId: string,
  planKey: string,
  actor: string,
): Record<string, unknown> {
  return {
    version: 1,
    source,
    subscriptionId,
    planKey,
    migratedAt: FieldValue.serverTimestamp(),
    actor,
  };
}
