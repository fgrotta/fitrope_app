// Logica pura di idoneità all'iscrizione (mirror autoritativo di getCourseState.dart).
// Il client resta il gate UX; qui il server applica le STESSE regole come autorità,
// così rifiuta esattamente ciò che la UI già rifiuterebbe (nessun falso blocco sui
// flussi legittimi).
//
// NB: l'enforcement vale per chi passa dalle callable. Finché le firestore.rules
// non sono lockate (PR6), un client SDK può ancora scrivere direttamente i campi
// critici: l'autorità del server diventa EFFETTIVA solo con PR6 deployata.

import { UserSubscriptionRecord } from "./subscription";
import { canUserAccessCourse, familyForTypeTag } from "./courseTypes";

/** Corso a cui l'utente è attualmente iscritto (per il conteggio settimanale). */
export interface EnrolledCourse {
  uid: string;
  startMillis: number;
  primaryTag: string;
}

/** Disiscrizione registrata (per contare gli ingressi persi nella settimana). */
export interface CancelledRecord {
  entryLost: boolean;
  courseStartMillis: number;
  /** Tipologia primaria del corso originario, se ancora risolvibile; altrimenti null. */
  primaryTag: string | null;
}

export type SubscribeReason =
  | "OK"
  | "ALREADY_SUBSCRIBED"
  | "NO_ACCESS"
  | "FULL"
  | "EXPIRED"
  | "NO_ENTRIES"
  | "WEEKLY_LIMIT"
  | "NOT_ELIGIBLE";

/** Come scalare il credito quando l'iscrizione è consentita. */
export interface ConsumePlan {
  kind: "NONE" | "LEGACY_ENTRY" | "SUBSCRIPTION_ENTRY";
  /** Id del documento abbonamento da decrementare (solo SUBSCRIPTION_ENTRY). */
  subscriptionId?: string | null;
}

export interface SubscribeDecision {
  allowed: boolean;
  reason: SubscribeReason;
  consume: ConsumePlan;
}

/**
 * Inizio/fine (in millis) della settimana che contiene [courseStartMillis], in UTC
 * (lun 00:00:00.000 → dom 23:59:59.999).
 *
 * NB: il client (getCourseState.dart) calcola i bordi nel fuso locale dell'utente
 * (Europe/Rome); qui usiamo UTC perché le Cloud Functions girano in UTC. Le due
 * versioni divergono solo per corsi a cavallo della mezzanotte sul bordo settimana
 * — caso raro. Il client resta il gate UX primario; questo è un backstop. Eventuale
 * allineamento esatto (settimana Europe/Rome anche server-side) è un miglioramento
 * futuro.
 */
export function weekBoundsMillis(courseStartMillis: number): {
  start: number;
  end: number;
} {
  const d = new Date(courseStartMillis);
  const isoDow = (d.getUTCDay() + 6) % 7; // 0=lun .. 6=dom
  const start = Date.UTC(
    d.getUTCFullYear(),
    d.getUTCMonth(),
    d.getUTCDate() - isoDow
  );
  const end = start + 7 * 24 * 60 * 60 * 1000 - 1;
  return { start, end };
}

function inWeek(millis: number, bounds: { start: number; end: number }): boolean {
  return millis >= bounds.start && millis <= bounds.end;
}

/**
 * Conta gli ingressi settimanali usati (corsi attivi + disiscrizioni perse) nella
 * settimana di [courseStartMillis].
 *
 * - [typeTags] null  → conteggio GLOBALE (modello legacy temporale).
 * - [typeTags] set   → conta solo i corsi la cui tipologia primaria è in [typeTags]
 *   (scoping per famiglia, modello multi-abbonamento). Le disiscrizioni perse di
 *   corsi non più risolvibili (primaryTag null) vengono comunque contate, per non
 *   sotto-contare il limite (mirror di _countWeeklyEntriesForTags).
 */
export function countWeeklyEntries(
  courseStartMillis: number,
  enrolled: EnrolledCourse[],
  cancelled: CancelledRecord[],
  typeTags: Set<string> | null
): number {
  const bounds = weekBoundsMillis(courseStartMillis);
  const matchesType = (tag: string | null): boolean =>
    typeTags === null || (tag !== null && typeTags.has(tag));

  let active = 0;
  for (const c of enrolled) {
    if (inWeek(c.startMillis, bounds) && matchesType(c.primaryTag)) active += 1;
  }

  let lost = 0;
  for (const c of cancelled) {
    if (!c.entryLost) continue;
    if (!inWeek(c.courseStartMillis, bounds)) continue;
    // typeTags null → conta sempre; altrimenti conta se la tipologia combacia
    // o se il corso non è più risolvibile (primaryTag null).
    if (typeTags === null || c.primaryTag === null || typeTags.has(c.primaryTag)) {
      lost += 1;
    }
  }

  return active + lost;
}

/**
 * Abbonamenti che coprono la tipologia [coursePrimaryTag] (indipendentemente dalla
 * data). Mirror di _coveringSubscriptions: usato per l'accesso e per distinguere
 * "nessun abbonamento copre la tipologia" da "copre ma scaduto" (→ EXPIRED).
 */
export function coveringSubsByType(
  subs: UserSubscriptionRecord[],
  coursePrimaryTag: string
): UserSubscriptionRecord[] {
  return subs.filter((s) => s.courseTypeTags.includes(coursePrimaryTag));
}

/** Sottoinsieme di [covering] valido alla data del corso (startDate ≤ data ≤ endDate). */
export function validAtDate(
  covering: UserSubscriptionRecord[],
  courseStartMillis: number
): UserSubscriptionRecord[] {
  return covering.filter(
    (s) =>
      courseStartMillis >= s.startDateMillis &&
      courseStartMillis <= s.endDateMillis
  );
}

const TEMPORAL_TIPOLOGIE = new Set([
  "ABBONAMENTO_MENSILE",
  "ABBONAMENTO_TRIMESTRALE",
  "ABBONAMENTO_SEMESTRALE",
  "ABBONAMENTO_ANNUALE",
]);

export interface SubscribeInput {
  force: boolean;
  alreadySubscribed: boolean;
  courseFull: boolean;

  userTags: string[];
  courseTags: string[];
  coursePrimaryTag: string;
  courseStartMillis: number;
  /** Adesso (per scartare dal modello le voci di snapshot già scadute). */
  nowMillis: number;

  /**
   * Snapshot abbonamenti attivi. Può contenere voci SCADUTE (lo snapshot viene
   * ricalcolato solo alle scritture e non c'è cron di pulizia): vengono scartate
   * qui, così uno snapshot sporco non blocca il fallback legacy (un utente con
   * soli abbonamenti scaduti torna a usare i suoi crediti legacy).
   */
  activeSubscriptions: UserSubscriptionRecord[];

  // Campi legacy (usati solo se activeSubscriptions è vuoto).
  tipologia: string | null;
  entrateDisponibili: number | null;
  entrateSettimanali: number | null;
  fineIscrizioneMillis: number | null;

  /**
   * Conteggio ingressi settimanali già usati. Per il modello a abbonamenti è lo
   * scope-per-tipologia della tipologia del corso; per il legacy temporale è
   * globale. Lo calcola l'handler (richiede letture Firestore).
   *
   * NB: è UN solo conteggio condiviso tra gli abbonamenti FREQUENCY coprenti,
   * mentre il client conta per-abbonamento (scope = tag di quell'abbonamento).
   * Coincidono finché ogni piano concede esattamente 1 tag e vale il vincolo
   * max-1-attivo-per-famiglia (→ al più un FREQUENCY coprente). L'invariante
   * mono-tag è blindato da un test sul catalogo; se in futuro un piano
   * concedesse più tag, passare a conteggi per-abbonamento.
   */
  weeklyUsed: number;
}

/**
 * Decide se l'utente può iscriversi e come scalare il credito.
 *
 * Ordine (mirror getCourseState): già-iscritto → accesso → scadenza/limiti → pieno.
 * [force] (admin) bypassa capienza, accesso, scadenza e limiti, ma NON il
 * già-iscritto; consuma comunque il credito disponibile (senza andare negativo).
 */
export function evaluateSubscribe(input: SubscribeInput): SubscribeDecision {
  const none: ConsumePlan = { kind: "NONE" };

  if (input.alreadySubscribed) {
    return { allowed: false, reason: "ALREADY_SUBSCRIBED", consume: none };
  }

  // Selezione del modello: contano solo le voci NON scadute adesso. NB: una voce
  // scaduta a "adesso" non può comunque essere valida alla data del corso (i corsi
  // prenotabili sono futuri), quindi il filtro non cambia mai l'esito di
  // validCovering — sblocca solo il fallback legacy con snapshot stantii.
  const liveSubs = input.activeSubscriptions.filter(
    (s) => s.endDateMillis >= input.nowMillis
  );
  const useSubscriptions = liveSubs.length > 0;
  // coveringByType: copre la tipologia (no filtro data) → accesso + distinzione EXPIRED.
  // validCovering: anche valido alla data → idoneità/consumo.
  const coveringByType = useSubscriptions
    ? coveringSubsByType(liveSubs, input.coursePrimaryTag)
    : [];
  const validCovering = validAtDate(coveringByType, input.courseStartMillis);

  const hasTagAccess = canUserAccessCourse(input.userTags, input.courseTags);

  // Risolve il piano di consumo (quale credito scalare) ignorando i gate: serve
  // sia per il path normale sia per il force admin. Consuma solo un abbonamento
  // VALIDO alla data e CON ingressi residui: con copertura mista sulla stessa
  // tipologia (ENTRIES esaurito + FREQUENCY idoneo) l'idoneità viene dal
  // FREQUENCY → il consumo deve essere NONE, non l'ENTRIES a zero (altrimenti
  // l'handler rifiuterebbe un'iscrizione che evaluateSubscribe ha consentito).
  const consumePlan = (): ConsumePlan => {
    if (useSubscriptions) {
      const entrySub = validCovering.find(
        (s) => s.billingMode === "ENTRIES" && (s.remainingEntries ?? 0) > 0
      );
      if (entrySub) {
        return { kind: "SUBSCRIPTION_ENTRY", subscriptionId: entrySub.id ?? null };
      }
      return none; // FREQUENCY (o ENTRIES esaurito con FREQUENCY idoneo): nessun decremento
    }
    if (
      input.tipologia === "PACCHETTO_ENTRATE" ||
      input.tipologia === "ABBONAMENTO_PROVA"
    ) {
      return { kind: "LEGACY_ENTRY" };
    }
    return none; // temporale legacy: nessun decremento (vedi README)
  };

  if (input.force) {
    return { allowed: true, reason: "OK", consume: consumePlan() };
  }

  // Accesso: legacy = solo tag; multi-abbonamento = tag OPPURE copertura (no data).
  if (useSubscriptions) {
    if (!hasTagAccess && coveringByType.length === 0) {
      return { allowed: false, reason: "NO_ACCESS", consume: none };
    }
  } else if (!hasTagAccess) {
    return { allowed: false, reason: "NO_ACCESS", consume: none };
  }

  // Idoneità (crediti/limiti/scadenza).
  const limit = useSubscriptions
    ? evaluateCoveringLimit(input, coveringByType, validCovering)
    : evaluateLegacyLimit(input);
  if (limit !== null) {
    return { allowed: false, reason: limit, consume: none };
  }

  if (input.courseFull) {
    return { allowed: false, reason: "FULL", consume: none };
  }

  return { allowed: true, reason: "OK", consume: consumePlan() };
}

/** Ritorna il motivo del blocco, o null se idoneo (modello multi-abbonamento). */
function evaluateCoveringLimit(
  input: SubscribeInput,
  coveringByType: UserSubscriptionRecord[],
  validCovering: UserSubscriptionRecord[]
): SubscribeReason | null {
  if (coveringByType.length === 0) {
    // Accessibile via tag ma nessun abbonamento copre la tipologia: se la tipologia
    // ha una famiglia (Open/Hyrox/PT) serve un abbonamento → non idoneo; se non ha
    // famiglia (es. Hey Mamma) → nessun limite.
    const family = familyForTypeTag(input.coursePrimaryTag);
    return family === null ? null : "NOT_ELIGIBLE";
  }

  // Copre la tipologia ma nessuno è valido alla data → scaduto.
  if (validCovering.length === 0) return "EXPIRED";

  // Idoneo se ALMENO uno dei validi consente l'iscrizione.
  for (const s of validCovering) {
    if (s.billingMode === "ENTRIES") {
      if ((s.remainingEntries ?? 0) > 0) return null;
    } else {
      if (s.weeklyFrequency === null) return null; // illimitato
      if (input.weeklyUsed < s.weeklyFrequency) return null;
    }
  }

  return validCovering[0].billingMode === "ENTRIES" ? "NO_ENTRIES" : "WEEKLY_LIMIT";
}

/** Ritorna il motivo del blocco, o null se idoneo (modello legacy mono-abbonamento). */
function evaluateLegacyLimit(input: SubscribeInput): SubscribeReason | null {
  // Scadenza (solo legacy): se il corso è dopo fineIscrizione → scaduto.
  if (
    input.fineIscrizioneMillis !== null &&
    input.courseStartMillis > input.fineIscrizioneMillis
  ) {
    return "EXPIRED";
  }

  if (
    input.tipologia === "ABBONAMENTO_PROVA" ||
    input.tipologia === "PACCHETTO_ENTRATE"
  ) {
    return (input.entrateDisponibili ?? 0) > 0 ? null : "NO_ENTRIES";
  }

  if (input.tipologia !== null && TEMPORAL_TIPOLOGIE.has(input.tipologia)) {
    if (input.entrateSettimanali === null) return null; // nessun limite
    return input.weeklyUsed >= input.entrateSettimanali ? "WEEKLY_LIMIT" : null;
  }

  return "NOT_ELIGIBLE";
}
