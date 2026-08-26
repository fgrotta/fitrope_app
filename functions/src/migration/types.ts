export type ConversionStatus =
  | "CONVERTIBLE"
  | "IGNORED"
  | "ALREADY_APPLIED"
  | "SOURCE_DRIFT"
  | "TARGET_CONFLICT";

export type ReasonCode =
  | "OK"
  | "HEY_MAMMA"
  | "ROLE_NOT_USER"
  | "NO_EXACT_ENTRIES_PLAN"
  | "TRIAL_NOT_SUPPORTED"
  | "INVALID_LEGACY_TYPE"
  | "INVALID_TAG_SHAPE"
  | "INVALID_WEEKLY_FREQUENCY"
  | "MISSING_END_DATE"
  | "FUTURE_START"
  | "EXISTING_SUBSCRIPTION_CONFLICT"
  | "ALREADY_APPLIED";

export interface MigrationDecision<T> {
  conversionStatus: ConversionStatus;
  reasonCode: ReasonCode;
  reasonDetail: string;
  target: T | null;
}

export interface CourseMigrationTarget {
  courseType: "open" | "personal_trainer";
  tag: string | null;
  courseModelV2: true;
  tags: string[];
}

export interface SubscriptionMigrationTarget {
  id: string;
  userId: string;
  createdBy: "legacy-migration";
  planKey: string;
  family: "OPEN";
  billingMode: "FREQUENCY";
  courseTypeTags: ["Open"];
  weeklyFrequency: 2 | 3 | null;
  remainingEntries: null;
  startDateMillis: number;
  endDateMillis: number;
  createdAtMillis: number;
}

