// Logica pura di rimborso/perdita alla disiscrizione (server autoritativo).
//
// Mirror combinato di CourseUnsubscribeHelper.canUnsubscribe (finestre 8h/4h) e
// delle due funzioni client unsubscribeToCourse / forceUnsubscribeWithNoRefund.
//
// Finestre:
//  - crediti a ingressi (ENTRIES / PACCHETTO_ENTRATE / ABBONAMENTO_PROVA): 8h
//  - frequenza settimanale (FREQUENCY / abbonamenti temporali): 4h
//  - NONE (nessun credito/limite): nessuna finestra, sempre rimborso del posto.
//
// Entro la finestra l'ingresso si perde SOLO con conferma esplicita dell'utente
// (confirmedNoRefund). Senza conferma → l'operazione va rifiutata dal chiamante.
//
// La perdita NON è definitiva nell'istante della disdetta: la voce scritta in
// `cancelledEnrollments` è recuperabile nella giornata del corso disdetto (un
// ingresso perso viene assorbito da un'iscrizione attiva della stessa giornata,
// vedi countWeeklyEntries / countRecoverableEntries in eligibility.ts). Qui si
// decide COSA si perde; se poi si perda davvero è un fatto derivato.

export type CreditMode =
  | "ENTRIES_SUB" // abbonamento a ingressi (nuovo modello)
  | "FREQUENCY_SUB" // abbonamento a frequenza (nuovo modello)
  | "ENTRIES_LEGACY" // PACCHETTO_ENTRATE / ABBONAMENTO_PROVA
  | "FREQUENCY_LEGACY" // abbonamento temporale legacy
  | "NONE"; // nessun credito da gestire (libera solo il posto)

/**
 * Cosa è stato perso con la disdetta, cioè cosa è recuperabile nella giornata.
 *  - "ENTRY"       → un ingresso (credito legacy o remainingEntries): NON pesa
 *                    sul limite settimanale, si recupera non riscalando il credito.
 *  - "WEEKLY_SLOT" → uno slot settimanale di un piano a frequenza: pesa sul
 *                    limite settimanale, si recupera per netting del conteggio.
 */
export type LostKind = "ENTRY" | "WEEKLY_SLOT";

export interface RefundInput {
  creditMode: CreditMode;
  /** Id del documento abbonamento da ripristinare (solo ENTRIES_SUB). */
  subscriptionId?: string | null;
  minutesToStart: number;
  confirmedNoRefund: boolean;
  /**
   * Se la prenotazione ha REALMENTE scalato un ingresso (dal registro consumi).
   * `null`/assente = registro non disponibile (prenotazione pre-registro) → si
   * deduce dal [creditMode] corrente, come faceva il vecchio fallback.
   */
  consumedEntry?: boolean | null;
}

export interface RefundDecision {
  /** True → entro finestra senza conferma: il chiamante deve rifiutare l'operazione. */
  requiresConfirmation: boolean;
  /** +1 a entrateDisponibili (legacy). */
  restoreLegacyEntry: boolean;
  /** +1 a remainingEntries dell'abbonamento [subscriptionId]. */
  restoreSubscriptionEntry: boolean;
  subscriptionId: string | null;
  /** Registra una voce in cancelledEnrollments. */
  trackCancelled: boolean;
  /** entryLost della voce cancelledEnrollments (true = qualcosa è stato perso). */
  entryLost: boolean;
  /** Cosa è stato perso (null se non si è perso nulla). */
  lostKind: LostKind | null;
}

const WINDOW_HOURS: Record<CreditMode, number | null> = {
  ENTRIES_SUB: 8,
  ENTRIES_LEGACY: 8,
  FREQUENCY_SUB: 4,
  FREQUENCY_LEGACY: 4,
  NONE: null,
};

const ENTRY_MODES = new Set<CreditMode>(["ENTRIES_SUB", "ENTRIES_LEGACY"]);
const FREQUENCY_MODES = new Set<CreditMode>(["FREQUENCY_SUB", "FREQUENCY_LEGACY"]);

const NO_OP: RefundDecision = {
  requiresConfirmation: false,
  restoreLegacyEntry: false,
  restoreSubscriptionEntry: false,
  subscriptionId: null,
  trackCancelled: false,
  entryLost: false,
  lostKind: null,
};

/**
 * Rimborso per le operazioni ADMIN su altri utenti (rimozione/disiscrizione
 * forzata, cancellazione corso): regola README "le funzioni admin rimborsano
 * SEMPRE" — nessuna finestra, nessuna conferma, nessuna perdita, e nessuna
 * voce in cancelledEnrollments (non è una disiscrizione volontaria: non deve
 * pesare sul limite settimanale né sullo storico disiscrizioni dell'utente).
 */
export function decideAdminRefund(
  creditMode: CreditMode,
  subscriptionId?: string | null
): RefundDecision {
  switch (creditMode) {
    case "ENTRIES_SUB":
      return {
        ...NO_OP,
        restoreSubscriptionEntry: true,
        subscriptionId: subscriptionId ?? null,
      };
    case "ENTRIES_LEGACY":
      return { ...NO_OP, restoreLegacyEntry: true };
    case "FREQUENCY_SUB":
    case "FREQUENCY_LEGACY":
    case "NONE":
      return { ...NO_OP };
  }
}

export function decideRefund(input: RefundInput): RefundDecision {
  const windowHours = WINDOW_HOURS[input.creditMode];
  const withinWindow =
    windowHours !== null && input.minutesToStart <= windowHours * 60;

  if (withinWindow && !input.confirmedNoRefund && input.creditMode !== "NONE") {
    return { ...NO_OP, requiresConfirmation: true };
  }

  // Si perde l'ingresso solo entro finestra E con conferma esplicita. Oltre la
  // finestra è sempre rimborso pieno (la conferma è irrilevante).
  const lose = withinWindow && input.confirmedNoRefund;

  // La PENALITÀ deve seguire la fonte REALMENTE consumata, altrimenti si paga
  // due volte. Caso concreto: prenotazione fatta col modello legacy (registro
  // LEGACY_ENTRY), poi l'utente passa a un abbonamento FREQUENCY; alla
  // disiscrizione entro finestra con conferma il creditMode risolto dal modello
  // ATTUALE è FREQUENCY_SUB, ma ciò che si perde è l'INGRESSO legacy, non uno
  // slot settimanale — se lo registrassimo come WEEKLY_SLOT peserebbe anche sul
  // limite settimanale.
  const consumedEntry =
    input.consumedEntry ?? ENTRY_MODES.has(input.creditMode);

  // Un piano a frequenza non scala nulla: la sua perdita è lo slot settimanale.
  // Se invece non è stato consumato NIENTE (force-subscribe con credito a zero)
  // non c'è alcuna penalità da registrare: registrarla inventerebbe una perdita.
  const lostSomething =
    lose && (consumedEntry || FREQUENCY_MODES.has(input.creditMode));
  const lostKind: LostKind | null = !lostSomething
    ? null
    : consumedEntry
      ? "ENTRY"
      : "WEEKLY_SLOT";

  // I modelli a frequenza tracciano SEMPRE la disdetta (storico), gli altri solo
  // quando c'è davvero una perdita da poter recuperare nella giornata.
  const trackCancelled = FREQUENCY_MODES.has(input.creditMode) || lostSomething;

  switch (input.creditMode) {
    case "ENTRIES_SUB":
      return {
        ...NO_OP,
        restoreSubscriptionEntry: !lose,
        subscriptionId: input.subscriptionId ?? null,
        trackCancelled,
        entryLost: lostSomething,
        lostKind,
      };
    case "ENTRIES_LEGACY":
      return {
        ...NO_OP,
        restoreLegacyEntry: !lose,
        trackCancelled,
        entryLost: lostSomething,
        lostKind,
      };
    case "FREQUENCY_SUB":
    case "FREQUENCY_LEGACY":
      return {
        ...NO_OP,
        trackCancelled,
        entryLost: lostSomething,
        lostKind,
      };
    case "NONE":
      return { ...NO_OP };
  }
}
