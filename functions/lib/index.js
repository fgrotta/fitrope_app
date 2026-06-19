"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendCertificateExpiryEmails = exports.sendTestCertificateEmail = exports.removeOneSignalEmail = exports.ensureOneSignalUser = exports.sendOneSignalNotification = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const params_1 = require("firebase-functions/params");
const handler_1 = require("./handler");
const certificateEmails_1 = require("./certificateEmails");
const firebaseAdmin_1 = require("./firebaseAdmin");
// Secret gestito da Google Secret Manager.
// Setup: firebase functions:secrets:set ONESIGNAL_REST_API_KEY
const oneSignalApiKey = (0, params_1.defineSecret)("ONESIGNAL_REST_API_KEY");
/**
 * Proxy verso OneSignal REST API.
 * Il client invia il body OneSignal già formattato (include_aliases, headings,
 * contents, target_channel, send_after, email_subject, email_body, ...).
 */
exports.sendOneSignalNotification = (0, https_1.onCall)({
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
}, (request) => (0, handler_1.sendOneSignalNotificationHandler)({ auth: request.auth ?? null, data: request.data }, oneSignalApiKey.value()));
/**
 * Crea o aggiorna l'utente OneSignal con la sua email subscription.
 * Va chiamata al login per garantire che l'utente esista sul backend OneSignal
 * prima di poter ricevere notifiche email via `include_aliases.external_id`.
 *
 * Payload atteso: { externalId: string, email?: string }
 */
exports.ensureOneSignalUser = (0, https_1.onCall)({
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
}, (request) => (0, handler_1.ensureOneSignalUserHandler)({ auth: request.auth ?? null, data: request.data }, oneSignalApiKey.value()));
/**
 * Disabilita la subscription email OneSignal dell'utente autenticato.
 *
 * Payload atteso: { email: string }
 */
exports.removeOneSignalEmail = (0, https_1.onCall)({
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
}, (request) => (0, handler_1.removeOneSignalEmailHandler)({ auth: request.auth ?? null, data: request.data }, oneSignalApiKey.value()));
/**
 * Invia un'email di test sulla scadenza del certificato medico a un singolo
 * utente (usata dalla DebugEmailPage). Renderizza il template server-side.
 *
 * Payload atteso: { externalId: string, firstName?: string, kind?: "reminder10" | "expiryToday" }
 */
exports.sendTestCertificateEmail = (0, https_1.onCall)({
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
}, (request) => (0, certificateEmails_1.sendTestCertificateEmailHandler)({ auth: request.auth ?? null, data: request.data }, oneSignalApiKey.value()));
/**
 * Cloud Function schedulata: ogni giorno alle 09:00 (ora di Roma) invia le email
 * sulla scadenza del certificato medico — promemoria a chi scade tra 10 giorni e
 * avviso a chi scade oggi. Rilegge lo stato attuale di Firestore (gestisce
 * rinnovi e certificati già esistenti senza scheduling futuro su OneSignal).
 */
exports.sendCertificateExpiryEmails = (0, scheduler_1.onSchedule)({
    schedule: "0 9 * * *",
    timeZone: "Europe/Rome",
    // NB: Cloud Scheduler non supporta europe-west8 (Milano), a differenza di
    // Cloud Functions. La funzione schedulata sta quindi in europe-west1; la
    // region qui è ininfluente (query Firestore + OneSignal via HTTPS) e il
    // timeZone garantisce comunque lo scatto alle 09:00 ora di Roma.
    region: "europe-west1",
    secrets: [oneSignalApiKey],
    timeoutSeconds: 300,
}, async () => {
    await (0, certificateEmails_1.runCertificateEmails)({
        db: firebaseAdmin_1.db,
        apiKey: oneSignalApiKey.value(),
        post: handler_1.postToOneSignal,
        ensure: handler_1.ensureOneSignalEmailSubscription,
        now: new Date(),
    });
});
//# sourceMappingURL=index.js.map