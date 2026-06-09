import { onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
  sendOneSignalNotificationHandler,
  ensureOneSignalUserHandler,
  removeOneSignalEmailHandler,
} from "./handler";

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
