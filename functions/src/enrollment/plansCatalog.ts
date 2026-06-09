// Mirror server-side del catalogo piani Dart (lib/utils/subscription_plans.dart).
// Le CHIAVI devono restare identiche tra client e server.

export type SubscriptionFamily = "OPEN" | "HYROX" | "PT";
export type BillingMode = "FREQUENCY" | "ENTRIES";

export interface SubscriptionPlan {
  key: string;
  displayName: string;
  family: SubscriptionFamily;
  billingMode: BillingMode;
  weeklyFrequency: number | null; // FREQUENCY: 2|3|null(illimitato)
  entries: number | null; // ENTRIES
  durationMonths: number; // 1|3|6|12
  grantedCourseTypeTags: string[];
}

export const DURATIONS = [1, 3, 6, 12];
export const ENTRIES_PER_PACKAGE = 10;

// Devono combaciare con CourseTags (lib/utils/course_tags.dart).
export const TAG_OPEN = "Open";
export const TAG_HYROX = "Hyrox";
export const TAG_PT = "Personal Trainer";

function durLabel(m: number): string {
  return m === 1 ? "1 mese" : `${m} mesi`;
}

function openPlans(): SubscriptionPlan[] {
  const plans: SubscriptionPlan[] = [];
  for (const d of DURATIONS) {
    plans.push({
      key: `open_2x_${d}m`,
      displayName: `Open 2 volte/sett · ${durLabel(d)}`,
      family: "OPEN",
      billingMode: "FREQUENCY",
      weeklyFrequency: 2,
      entries: null,
      durationMonths: d,
      grantedCourseTypeTags: [TAG_OPEN],
    });
    plans.push({
      key: `open_3x_${d}m`,
      displayName: `Open 3 volte/sett · ${durLabel(d)}`,
      family: "OPEN",
      billingMode: "FREQUENCY",
      weeklyFrequency: 3,
      entries: null,
      durationMonths: d,
      grantedCourseTypeTags: [TAG_OPEN],
    });
    plans.push({
      key: `open_unlim_${d}m`,
      displayName: `Open illimitato · ${durLabel(d)}`,
      family: "OPEN",
      billingMode: "FREQUENCY",
      weeklyFrequency: null,
      entries: null,
      durationMonths: d,
      grantedCourseTypeTags: [TAG_OPEN],
    });
  }
  return plans;
}

function entriesPlans(
  family: SubscriptionFamily,
  prefix: string,
  label: string,
  tag: string
): SubscriptionPlan[] {
  return DURATIONS.map((d) => ({
    key: `${prefix}_${ENTRIES_PER_PACKAGE}i_${d}m`,
    displayName: `${label} ${ENTRIES_PER_PACKAGE} ingressi · ${durLabel(d)}`,
    family,
    billingMode: "ENTRIES" as BillingMode,
    weeklyFrequency: null,
    entries: ENTRIES_PER_PACKAGE,
    durationMonths: d,
    grantedCourseTypeTags: [tag],
  }));
}

export const SUBSCRIPTION_PLANS: SubscriptionPlan[] = [
  ...openPlans(),
  ...entriesPlans("HYROX", "hyrox", "Hyrox", TAG_HYROX),
  ...entriesPlans("PT", "pt", "PT", TAG_PT),
];

export function planByKey(key: string): SubscriptionPlan | undefined {
  return SUBSCRIPTION_PLANS.find((p) => p.key === key);
}
