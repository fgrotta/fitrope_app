import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import {
  sendOneSignalNotificationHandler,
  ensureOneSignalUserHandler,
  removeOneSignalEmailHandler,
  ensureOneSignalEmailSubscription,
  postToOneSignal,
} from "./handler";
import {
  runCertificateEmails,
  sendTestCertificateEmailHandler,
} from "./certificateEmails";
import { assignSubscriptionHandler } from "./enrollment/assignSubscription";
import {
  subscribeToCourseHandler,
  unsubscribeFromCourseHandler,
  joinWaitlistHandler,
  leaveWaitlistHandler,
} from "./enrollment/enrollment";
import {
  deleteCourseHandler,
  recountCourseSubscribedHandler,
} from "./enrollment/admin";
import {
  scheduleTrialReminder,
  notifyWaitlistUsers,
} from "./enrollment/notify";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

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
      oneSignalApiKey.value(),
      { db: admin.firestore(), ensure: ensureOneSignalEmailSubscription }
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
 * Assegna un abbonamento a un utente (solo Admin). Crea il documento in
 * `subscriptions` e ricalcola lo snapshot `activeSubscriptions` sul doc utente.
 *
 * Payload atteso: { userId: string, planKey: string, startDateMillis?: number }
 */
export const assignSubscription = onCall(
  {
    region: "europe-west8",
    cors: true,
  },
  (request) =>
    assignSubscriptionHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore()
    )
);

/**
 * Iscrizione a un corso (server-authoritative): valida idoneità/capienza, scala
 * gli ingressi dell'abbonamento giusto e aggiorna lo snapshot, in transazione.
 *
 * Payload: { courseId: string, userId: string, force?: boolean }
 */
export const subscribeToCourse = onCall(
  { region: "europe-west8", cors: true, secrets: [oneSignalApiKey] },
  (request) =>
    subscribeToCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
      {
        notifyTrialReminder: (userId, courseId) =>
          scheduleTrialReminder(
            admin.firestore(),
            oneSignalApiKey.value(),
            userId,
            courseId,
            Date.now()
          ),
      }
    )
);

/**
 * Disiscrizione da un corso: applica le finestre di rimborso (8h ingressi / 4h
 * frequenza), ripristina il credito dovuto, traccia le disiscrizioni perse e
 * notifica la waitlist, in transazione.
 *
 * Payload: { courseId: string, userId: string, confirmedNoRefund?: boolean }
 */
export const unsubscribeFromCourse = onCall(
  { region: "europe-west8", cors: true, secrets: [oneSignalApiKey] },
  (request) =>
    unsubscribeFromCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
      {
        notifyWaitlist: (courseId) =>
          notifyWaitlistUsers(admin.firestore(), oneSignalApiKey.value(), courseId),
      }
    )
);

/**
 * Iscrizione alla lista d'attesa di un corso pieno.
 *
 * Payload: { courseId: string, userId: string }
 */
export const joinWaitlist = onCall(
  { region: "europe-west8", cors: true },
  (request) =>
    joinWaitlistHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore()
    )
);

/**
 * Rimozione dalla lista d'attesa (self oppure Admin/Trainer su altri).
 *
 * Payload: { courseId: string, userId: string }
 */
export const leaveWaitlist = onCall(
  { region: "europe-west8", cors: true },
  (request) =>
    leaveWaitlistHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore()
    )
);

/**
 * Cancella un corso rimborsando tutti gli iscritti e ripulendo le waitlist
 * (Admin/Trainer), in una transazione atomica.
 *
 * Payload: { courseId: string }
 */
export const deleteCourse = onCall(
  { region: "europe-west8", cors: true },
  (request) =>
    deleteCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore()
    )
);

/**
 * Ricalcola il contatore `subscribed` di un corso dalla fonte di verità
 * (Admin/Trainer). Sostituisce la correzione manuale client-side.
 *
 * Payload: { courseId: string }
 */
export const recountCourseSubscribed = onCall(
  { region: "europe-west8", cors: true },
  (request) =>
    recountCourseSubscribedHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore()
    )
);

// ──────────────────────────────────────────────
//  Email certificati — SOLO emulatore e staging
// ──────────────────────────────────────────────
//
// Le funzioni certificati non devono esistere in produzione finché la feature
// non viene promossa. Il gate agisce in fase di DISCOVERY: la CLI Firebase
// carica `.env.<projectId>` prima di enumerare gli export, quindi su staging
// (`.env.fit-rope-staging` con APP_ENV=staging, scritto da staging.yml) le
// funzioni vengono deployate, mentre in prod — dove quel file non esiste —
// l'export è undefined e la CLI le ignora. Sull'emulatore il runtime imposta
// FUNCTIONS_EMULATOR=true. La stessa condizione è rivalutata a runtime come
// guardia difensiva contro un deploy con env sbagliata.
function certificateFunctionsEnabled(): boolean {
  return (
    process.env.APP_ENV === "staging" ||
    process.env.FUNCTIONS_EMULATOR === "true"
  );
}

/**
 * Invio di test delle email certificato (DebugEmailPage, kDebugMode).
 * Payload: { externalId: string, firstName?: string, kind?: "reminder10"|"expiryToday", email?: string }
 */
export const sendTestCertificateEmail = certificateFunctionsEnabled()
  ? onCall(
      { secrets: [oneSignalApiKey], region: "europe-west8", cors: true },
      (request) => {
        if (!certificateFunctionsEnabled()) {
          throw new HttpsError(
            "failed-precondition",
            "Funzione disponibile solo su emulatore e staging"
          );
        }
        return sendTestCertificateEmailHandler(
          { auth: request.auth ?? null, data: request.data },
          oneSignalApiKey.value()
        );
      }
    )
  : undefined;

/**
 * Run giornaliero delle email certificato: promemoria a chi scade tra 10 giorni
 * e avviso a chi scade oggi (08:00 Europe/Rome). In staging gli invii restano
 * comunque filtrati dalla allowlist dentro postToOneSignal/ensure (UID stg_ +
 * STAGING_NOTIFICATION_EMAIL_ALLOWLIST).
 */
export const certificateEmailsDaily = certificateFunctionsEnabled()
  ? onSchedule(
      {
        schedule: "0 8 * * *",
        timeZone: "Europe/Rome",
        region: "europe-west8",
        secrets: [oneSignalApiKey],
      },
      async () => {
        if (!certificateFunctionsEnabled()) {
          logger.warn(
            "certificateEmailsDaily invocata fuori da emulatore/staging: no-op"
          );
          return;
        }
        await runCertificateEmails({
          db: admin.firestore(),
          apiKey: oneSignalApiKey.value(),
          post: postToOneSignal,
          ensure: ensureOneSignalEmailSubscription,
          now: new Date(),
        });
      }
    )
  : undefined;
