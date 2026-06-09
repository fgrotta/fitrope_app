"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.removeOneSignalEmail = exports.ensureOneSignalUser = exports.sendOneSignalNotification = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const handler_1 = require("./handler");
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
//# sourceMappingURL=index.js.map