// Predicato "utente di prova", condiviso tra iscrizione (subscribeToCourseHandler)
// e promemoria WhatsApp (whatsapp/reminders.ts).
//
// Estratto da subscribeToCourseHandler senza cambiarne il comportamento: un
// utente è di prova se ha un abbonamento vivo sul piano di prova, oppure se è
// ancora sul modello legacy (nessun abbonamento vivo, subscriptionModelVersion
// < 2) con tipologia ABBONAMENTO_PROVA. Uno snapshot vivo di altro tipo
// significa che l'utente è stato convertito al multi-abbonamento, anche se la
// tipologia legacy è rimasta PROVA: in quel caso NON è di prova.

import type { DocumentData } from "firebase-admin/firestore";
import { UserSubscriptionRecord } from "./subscription";

/** Chiave del piano "Prova Open · 1 ingresso · 30 giorni" (plansCatalog.ts). */
export const TRIAL_PLAN_KEY = "open_trial_1i_30d";

export function isTrialUser(
  user: DocumentData,
  liveRecords: UserSubscriptionRecord[]
): boolean {
  if (liveRecords.some((record) => record.planKey === TRIAL_PLAN_KEY)) {
    return true;
  }
  return (
    liveRecords.length === 0 &&
    ((user.subscriptionModelVersion as number | null) ?? 1) < 2 &&
    user.tipologiaIscrizione === "ABBONAMENTO_PROVA"
  );
}
