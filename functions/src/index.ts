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
import {
  MakeDeps,
  notifyDemoLessonBookedHandler,
  postToMake,
  runDemoLessonReminders,
  sendTestDemoLessonWebhookHandler,
} from "./makeWebhook";
import { db } from "./firebaseAdmin";

// Secret gestiti da Google Secret Manager.
// Setup: firebase functions:secrets:set ONESIGNAL_REST_API_KEY
const oneSignalApiKey = defineSecret("ONESIGNAL_REST_API_KEY");

// URL del Custom webhook Make e chiave inviata nell'header `Demo-Reminder`.
// L'URL è a tutti gli effetti una credenziale: chi lo conosce può iniettare
// messaggi WhatsApp a nostro nome, quindi non va mai in chiaro nel repo.
// Setup: firebase functions:secrets:set MAKE_WEBHOOK_URL
//        firebase functions:secrets:set MAKE_WEBHOOK_KEY
const makeWebhookUrl = defineSecret("MAKE_WEBHOOK_URL");
const makeWebhookKey = defineSecret("MAKE_WEBHOOK_KEY");

const makeSecrets = [makeWebhookUrl, makeWebhookKey];

/** Dipendenze del modulo Make, risolte a runtime (i secret non sono leggibili a import-time). */
const makeDeps = (): MakeDeps => ({
  db,
  webhookUrl: makeWebhookUrl.value(),
  apiKey: makeWebhookKey.value(),
  post: postToMake,
  now: new Date(),
});

/**
 * Proxy verso OneSignal REST API.
 * Il client invia il body OneSignal già formattato (include_aliases, headings,
 * contents, target_channel, send_after, email_subject, email_body, ...).
 * Per gli invii email mirati garantisce server-side che ogni destinatario
 * esista su OneSignal (ensure idempotente) prima della POST.
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
      oneSignalApiKey.value(),
      { db, ensure: ensureOneSignalEmailSubscription }
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

/**
 * Notifica via webhook Make la prenotazione di una lezione di prova, per far
 * partire il messaggio WhatsApp di conferma.
 *
 * Il client passa solo gli identificativi: utente e corso vengono riletti da
 * Firestore server-side, che è anche l'unica autorità su "è un utente di prova".
 *
 * Payload atteso: { userId: string, courseId: string }
 */
export const notifyDemoLessonBooked = onCall(
  {
    secrets: makeSecrets,
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    notifyDemoLessonBookedHandler(
      { auth: request.auth ?? null, data: request.data },
      makeDeps()
    )
);

/**
 * Manda un payload di prova al webhook Make, al numero indicato dal chiamante
 * (usata dalla DebugEmailPage). Non tocca Firestore e non registra l'invio.
 *
 * Payload atteso: { numeroTelefono: string, kind?: "booked" | "reminder", nome?: string, corso?: string }
 */
export const sendTestDemoLessonWebhook = onCall(
  {
    secrets: makeSecrets,
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    sendTestDemoLessonWebhookHandler(
      { auth: request.auth ?? null, data: request.data },
      makeDeps()
    )
);

/**
 * Cloud Function schedulata: ogni sera alle 19:00 (ora di Roma) manda il
 * promemoria WhatsApp agli utenti di prova iscritti a una lezione di domani.
 *
 * A differenza del promemoria email/push — programmato su OneSignal dal
 * dispositivo al momento dell'iscrizione, e quindi non più annullabile — qui i
 * destinatari sono decisi al momento dell'invio: chi si è disiscritto, o il cui
 * corso è stato cancellato, semplicemente non compare nella query.
 */
export const sendDemoLessonWhatsappReminders = onSchedule(
  {
    schedule: "0 19 * * *",
    timeZone: "Europe/Rome",
    // NB: come sendCertificateExpiryEmails — Cloud Scheduler non supporta
    // europe-west8 (Milano), quindi la schedulata sta in europe-west1. La
    // region è ininfluente (Firestore + HTTPS) e il timeZone garantisce lo
    // scatto alle 19:00 ora di Roma.
    region: "europe-west1",
    secrets: makeSecrets,
    timeoutSeconds: 300,
  },
  async () => {
    await runDemoLessonReminders(makeDeps());
  }
);
