import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
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
  /** Revoca Admin (storico): il documento resta, ma non entra mai nello snapshot. */
  revokedAtMillis?: number | null;
  /**
   * Tetto dei rimborsi per un pacchetto a cui l'Admin ha dato più ingressi del
   * piano (`updateSubscription`). Assente = gli ingressi del piano.
   */
  maxEntries?: number | null;
}

/** Tetto di un ripristino di ingresso: `maxEntries` se presente, altrimenti il piano. */
export function entriesCeiling(r: UserSubscriptionRecord): number | null {
  return r.maxEntries ?? planByKey(r.planKey)?.entries ?? null;
}

// Limiti della finestra accettata dalle callable: fuori da questo intervallo
// la data è quasi certamente un errore di input (anno a due cifre, millis/secondi).
const MIN_WINDOW_MILLIS = Date.UTC(2020, 0, 1);
const MAX_WINDOW_MILLIS = Date.UTC(2100, 0, 1);

/**
 * Valida la finestra di un abbonamento ricevuta da una callable: millis interi
 * e finiti (niente NaN), fine successiva all'inizio, entrambe tra il 2020 e il 2100.
 */
export function validateWindow(startMillis: unknown, endMillis: unknown): void {
  const valid = (v: unknown): v is number =>
    typeof v === "number" && Number.isFinite(v) && Number.isInteger(v) &&
    v >= MIN_WINDOW_MILLIS && v <= MAX_WINDOW_MILLIS;
  if (!valid(startMillis) || !valid(endMillis)) {
    throw new HttpsError("invalid-argument", "Date dell'abbonamento non valide");
  }
  if (endMillis <= startMillis) {
    throw new HttpsError(
      "invalid-argument",
      "La data di fine deve essere successiva alla data di inizio",
    );
  }
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

/** Fine predefinita di un abbonamento del piano [plan] che inizia a [startMillis]. */
export function defaultEndMillis(plan: SubscriptionPlan, startMillis: number): number {
  return plan.durationDays !== null
    ? startMillis + plan.durationDays * 86400000
    : addMonths(startMillis, plan.durationMonths!);
}

/**
 * Costruisce un abbonamento dal piano. Senza [endMillis] la durata del piano
 * determina la finestra di validità.
 */
export function buildSubscriptionFromPlan(
  plan: SubscriptionPlan,
  startMillis: number,
  endMillis?: number
): UserSubscriptionRecord {
  return {
    planKey: plan.key,
    family: plan.family,
    billingMode: plan.billingMode,
    courseTypeTags: [...plan.grantedCourseTypeTags],
    weeklyFrequency: plan.weeklyFrequency,
    remainingEntries: plan.billingMode === "ENTRIES" ? plan.entries : null,
    startDateMillis: startMillis,
    endDateMillis: endMillis ?? defaultEndMillis(plan, startMillis),
  };
}

/**
 * Snapshot degli abbonamenti non revocati e non ancora scaduti alla data
 * [nowMillis], compresi quelli con inizio futuro: nessun job li aggiungerebbe
 * allo snapshot quando la data arriva. L'inizio rispetto alla data del corso
 * lo controllano già validAtDate (server) e getCourseState (client).
 */
export function computeActiveSnapshot(
  records: UserSubscriptionRecord[],
  nowMillis: number
): UserSubscriptionRecord[] {
  return records.filter(
    (r) => !r.revokedAtMillis && r.endDateMillis >= nowMillis
  );
}

/**
 * Abbonamenti non revocati della famiglia [family] la cui finestra si
 * sovrappone a [startMillis, endMillis] (vincolo: max 1 per famiglia alla
 * volta). [excludeId] esclude l'abbonamento che si sta modificando.
 */
export function findOverlapping(
  records: UserSubscriptionRecord[],
  family: SubscriptionFamily,
  startMillis: number,
  endMillis: number,
  excludeId?: string
): UserSubscriptionRecord[] {
  return records.filter(
    (r) => !r.revokedAtMillis && r.family === family &&
      (excludeId === undefined || r.id !== excludeId) &&
      r.startDateMillis <= endMillis && r.endDateMillis >= startMillis
  );
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
    ...(data.revokedAt && typeof data.revokedAt.toMillis === "function"
      ? { revokedAtMillis: data.revokedAt.toMillis() as number }
      : {}),
    ...(typeof data.maxEntries === "number" && Number.isInteger(data.maxEntries)
      ? { maxEntries: data.maxEntries as number }
      : {}),
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
