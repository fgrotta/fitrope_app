import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  SubscriptionPlan,
  SubscriptionFamily,
  BillingMode,
  planByKey,
} from "./plansCatalog";

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

type FsData = admin.firestore.DocumentData;

/** Record (millis) da un documento Firestore della collezione `subscriptions`. */
export function recordFromDoc(id: string, data: FsData): UserSubscriptionRecord {
  const plan = typeof data.planKey === "string" ? planByKey(data.planKey) : null;
  if (!plan) {
    throw new Error(`planKey sconosciuto: ${String(data.planKey)}`);
  }
  if (data.family !== plan.family) {
    throw new Error(`family non valida per ${plan.key}: ${String(data.family)}`);
  }
  if (data.billingMode !== plan.billingMode) {
    throw new Error(
      `billingMode non valido per ${plan.key}: ${String(data.billingMode)}`
    );
  }
  if (!Array.isArray(data.courseTypeTags) ||
      data.courseTypeTags.length !== plan.grantedCourseTypeTags.length ||
      data.courseTypeTags.some(
        (value: unknown, index: number) =>
          value !== plan.grantedCourseTypeTags[index]
      )) {
    throw new Error(`courseTypeTags non validi per ${plan.key}`);
  }
  if (plan.billingMode === "FREQUENCY") {
    if (data.weeklyFrequency !== plan.weeklyFrequency ||
        (data.remainingEntries ?? null) !== null) {
      throw new Error(`limiti FREQUENCY non validi per ${plan.key}`);
    }
  } else if ((data.weeklyFrequency ?? null) !== null ||
      typeof data.remainingEntries !== "number" ||
      !Number.isInteger(data.remainingEntries) || data.remainingEntries < 0) {
    throw new Error(`crediti ENTRIES non validi per ${plan.key}`);
  }
  const start = data.startDate;
  const end = data.endDate;
  if (!start || typeof start.toMillis !== "function" ||
      !end || typeof end.toMillis !== "function") {
    throw new Error(`date non valide per ${plan.key}`);
  }
  return {
    id,
    planKey: data.planKey,
    family: data.family,
    billingMode: data.billingMode,
    courseTypeTags: data.courseTypeTags,
    weeklyFrequency: data.weeklyFrequency ?? null,
    remainingEntries: data.remainingEntries ?? null,
    startDateMillis: start.toMillis(),
    endDateMillis: end.toMillis(),
  };
}

/** Documento Firestore (collezione `subscriptions`) da un record. */
export function recordToDoc(
  r: UserSubscriptionRecord,
  userId: string,
  createdBy: string
): FsData {
  return {
    userId,
    createdBy,
    planKey: r.planKey,
    family: r.family,
    billingMode: r.billingMode,
    courseTypeTags: r.courseTypeTags,
    weeklyFrequency: r.weeklyFrequency,
    remainingEntries: r.remainingEntries,
    startDate: Timestamp.fromMillis(r.startDateMillis),
    endDate: Timestamp.fromMillis(r.endDateMillis),
    createdAt: Timestamp.now(),
  };
}

/** Voce dello snapshot `activeSubscriptions` sul doc utente (mappa su Dart UserSubscription). */
export function recordToSnapshotEntry(r: UserSubscriptionRecord): FsData {
  return {
    id: r.id ?? null,
    planKey: r.planKey,
    family: r.family,
    billingMode: r.billingMode,
    courseTypeTags: r.courseTypeTags,
    weeklyFrequency: r.weeklyFrequency,
    remainingEntries: r.remainingEntries,
    startDate: Timestamp.fromMillis(r.startDateMillis),
    endDate: Timestamp.fromMillis(r.endDateMillis),
  };
}
