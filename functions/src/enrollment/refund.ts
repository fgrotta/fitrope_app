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

export type CreditMode =
  | "ENTRIES_SUB" // abbonamento a ingressi (nuovo modello)
  | "FREQUENCY_SUB" // abbonamento a frequenza (nuovo modello)
  | "ENTRIES_LEGACY" // PACCHETTO_ENTRATE / ABBONAMENTO_PROVA
  | "FREQUENCY_LEGACY" // abbonamento temporale legacy
  | "NONE"; // nessun credito da gestire (libera solo il posto)

export interface RefundInput {
  creditMode: CreditMode;
  /** Id del documento abbonamento da ripristinare (solo ENTRIES_SUB). */
  subscriptionId?: string | null;
  minutesToStart: number;
  confirmedNoRefund: boolean;
}

export interface RefundDecision {
  /** True → entro finestra senza conferma: il chiamante deve rifiutare l'operazione. */
  requiresConfirmation: boolean;
  /** +1 a entrateDisponibili (legacy). */
  restoreLegacyEntry: boolean;
  /** +1 a remainingEntries dell'abbonamento [subscriptionId]. */
  restoreSubscriptionEntry: boolean;
  subscriptionId: string | null;
  /** Registra una voce in cancelledEnrollments (solo modello a frequenza). */
  trackCancelled: boolean;
  /** entryLost della voce cancelledEnrollments (true = ingresso settimanale perso). */
  entryLost: boolean;
}

const WINDOW_HOURS: Record<CreditMode, number | null> = {
  ENTRIES_SUB: 8,
  ENTRIES_LEGACY: 8,
  FREQUENCY_SUB: 4,
  FREQUENCY_LEGACY: 4,
  NONE: null,
};

const NO_OP: RefundDecision = {
  requiresConfirmation: false,
  restoreLegacyEntry: false,
  restoreSubscriptionEntry: false,
  subscriptionId: null,
  trackCancelled: false,
  entryLost: false,
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

  switch (input.creditMode) {
    case "ENTRIES_SUB":
      return {
        ...NO_OP,
        restoreSubscriptionEntry: !lose,
        subscriptionId: input.subscriptionId ?? null,
        entryLost: lose,
      };
    case "ENTRIES_LEGACY":
      return { ...NO_OP, restoreLegacyEntry: !lose, entryLost: lose };
    case "FREQUENCY_SUB":
    case "FREQUENCY_LEGACY":
      return { ...NO_OP, trackCancelled: true, entryLost: lose };
    case "NONE":
      return { ...NO_OP };
  }
}
