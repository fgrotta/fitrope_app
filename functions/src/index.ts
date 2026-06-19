import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import {
  sendOneSignalNotificationHandler,
  ensureOneSignalUserHandler,
  removeOneSignalEmailHandler,
  postToOneSignal,
  ensureOneSignalEmailSubscription,
} from "./handler";
import {
  sendTestCertificateEmailHandler,
  runCertificateEmails,
} from "./certificateEmails";
import { db } from "./firebaseAdmin";

// Secret gestito da Google Secret Manager.
// Setup: firebase functions:secrets:set ONESIGNAL_REST_API_KEY
const oneSignalApiKey = defineSecret("ONESIGNAL_REST_API_KEY");

/**
 * Proxy verso OneSignal REST API.
 * Il client invia il body OneSignal già formattato (include_aliases, headings,
 * contents, target_channel, send_after, email_subject, email_body, ...).
 */
export const sendOneSignalNotification = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    sendOneSignalNotificationHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value()
    )
);

/**
 * Crea o aggiorna l'utente OneSignal con la sua email subscription.
 * Va chiamata al login per garantire che l'utente esista sul backend OneSignal
 * prima di poter ricevere notifiche email via `include_aliases.external_id`.
 *
 * Payload atteso: { externalId: string, email?: string }
 */
export const ensureOneSignalUser = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    ensureOneSignalUserHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value()
    )
);

/**
 * Disabilita la subscription email OneSignal dell'utente autenticato.
 *
 * Payload atteso: { email: string }
 */
export const removeOneSignalEmail = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    removeOneSignalEmailHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value()
    )
);

/**
 * Invia un'email di test sulla scadenza del certificato medico a un singolo
 * utente (usata dalla DebugEmailPage). Renderizza il template server-side.
 *
 * Payload atteso: { externalId: string, firstName?: string, kind?: "reminder10" | "expiryToday" }
 */
export const sendTestCertificateEmail = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    sendTestCertificateEmailHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value()
    )
);

/**
 * Cloud Function schedulata: ogni giorno alle 09:00 (ora di Roma) invia le email
 * sulla scadenza del certificato medico — promemoria a chi scade tra 10 giorni e
 * avviso a chi scade oggi. Rilegge lo stato attuale di Firestore (gestisce
 * rinnovi e certificati già esistenti senza scheduling futuro su OneSignal).
 */
export const sendCertificateExpiryEmails = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "Europe/Rome",
    // NB: Cloud Scheduler non supporta europe-west8 (Milano), a differenza di
    // Cloud Functions. La funzione schedulata sta quindi in europe-west1; la
    // region qui è ininfluente (query Firestore + OneSignal via HTTPS) e il
    // timeZone garantisce comunque lo scatto alle 09:00 ora di Roma.
    region: "europe-west1",
    secrets: [oneSignalApiKey],
    timeoutSeconds: 300,
  },
  async () => {
    await runCertificateEmails({
      db,
      apiKey: oneSignalApiKey.value(),
      post: postToOneSignal,
      ensure: ensureOneSignalEmailSubscription,
      now: new Date(),
    });
  }
);
