"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL = exports.ONESIGNAL_SUBSCRIPTIONS_URL = exports.ONESIGNAL_USERS_URL = exports.ONESIGNAL_API_URL = exports.ONESIGNAL_APP_ID = void 0;
exports.postToOneSignal = postToOneSignal;
exports.sendOneSignalNotificationHandler = sendOneSignalNotificationHandler;
exports.ensureOneSignalUserHandler = ensureOneSignalUserHandler;
exports.ensureOneSignalEmailSubscription = ensureOneSignalEmailSubscription;
exports.removeOneSignalEmailHandler = removeOneSignalEmailHandler;
const https_1 = require("firebase-functions/v2/https");
const firebase_functions_1 = require("firebase-functions");
exports.ONESIGNAL_APP_ID = "154fc17b-3ef8-4421-a1e6-466172fa48db";
exports.ONESIGNAL_API_URL = "https://api.onesignal.com/notifications";
exports.ONESIGNAL_USERS_URL = `https://api.onesignal.com/apps/${exports.ONESIGNAL_APP_ID}/users`;
exports.ONESIGNAL_SUBSCRIPTIONS_URL = `https://api.onesignal.com/apps/${exports.ONESIGNAL_APP_ID}/subscriptions`;
exports.ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL = `https://api.onesignal.com/apps/${exports.ONESIGNAL_APP_ID}/subscriptions_by_token`;
/**
 * Esegue la POST verso OneSignal e gestisce la risposta.
 * Condivisa tra l'handler onCall e le funzioni schedulate (che non hanno auth).
 * Il chiamante deve aver già iniettato `app_id` nel payload.
 */
async function postToOneSignal(payload, apiKey) {
    let response;
    try {
        response = await fetch(exports.ONESIGNAL_API_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                Authorization: `Key ${apiKey.trim()}`,
            },
            body: JSON.stringify(payload),
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("OneSignal fetch failed", err);
        throw new https_1.HttpsError("unavailable", "Impossibile contattare OneSignal");
    }
    const data = (await response.json());
    if (!response.ok) {
        firebase_functions_1.logger.error("OneSignal error", { status: response.status, data });
        const errors = data.errors?.join(", ") ?? "Errore OneSignal";
        throw new https_1.HttpsError("internal", errors);
    }
    firebase_functions_1.logger.info("OneSignal response", { status: response.status, data });
    return data;
}
/**
 * Logica di inoltro verso OneSignal REST API.
 * Esposta separatamente da `onCall` per poter essere testata senza dipendere
 * dall'infrastruttura Firebase Functions.
 *
 * - Verifica autenticazione
 * - Verifica payload
 * - Inietta app_id server-side
 * - Chiama OneSignal con la REST API key (passata come parametro)
 */
async function sendOneSignalNotificationHandler(request, apiKey) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Login richiesto");
    }
    const payload = request.data;
    if (!payload || typeof payload !== "object") {
        throw new https_1.HttpsError("invalid-argument", "Body mancante o invalido");
    }
    payload.app_id = exports.ONESIGNAL_APP_ID;
    const logPayload = { ...payload };
    delete logPayload.email_body;
    firebase_functions_1.logger.info("OneSignal request", {
        uid: request.auth.uid,
        payload: logPayload,
    });
    return postToOneSignal(payload, apiKey);
}
/**
 * Crea o aggiorna un utente OneSignal con l'email specificata come subscription.
 * Usa l'endpoint Users di OneSignal v2 per garantire che l'utente esista
 * prima di poter ricevere notifiche via `include_aliases.external_id`.
 *
 * Payload atteso dal client:
 *   { externalId: string, email?: string }
 *
 * Se l'utente esiste già (409 Conflict), aggiunge l'email come subscription
 * tramite l'endpoint delle subscriptions.
 */
async function ensureOneSignalUserHandler(request, apiKey) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Login richiesto");
    }
    const payload = request.data;
    if (!payload || typeof payload !== "object" || !payload.externalId) {
        throw new https_1.HttpsError("invalid-argument", "externalId obbligatorio");
    }
    return ensureOneSignalEmailSubscription(payload.externalId, payload.email?.trim(), apiKey);
}
/**
 * Crea/aggiorna la subscription email OneSignal per un external_id.
 * Estratta dall'handler onCall per essere riusata dalla Cloud Function
 * schedulata (che non ha contesto auth). Idempotente: se l'utente esiste già
 * (409) aggiunge l'email; se l'email esiste ma è disabilitata, la riabilita.
 * È la stessa logica usata al login.
 */
async function ensureOneSignalEmailSubscription(externalId, email, apiKey) {
    const body = {
        identity: { external_id: externalId },
    };
    if (email) {
        body.subscriptions = [
            { type: "Email", token: email, enabled: true },
        ];
    }
    firebase_functions_1.logger.info("OneSignal ensureUser request", {
        externalId,
        hasEmail: !!email,
    });
    const authHeader = `Key ${apiKey.trim()}`;
    let response;
    try {
        response = await fetch(exports.ONESIGNAL_USERS_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                Authorization: authHeader,
            },
            body: JSON.stringify(body),
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("OneSignal ensureUser fetch failed", err);
        throw new https_1.HttpsError("unavailable", "Impossibile contattare OneSignal");
    }
    const data = (await response.json().catch(() => ({})));
    // 200/201: creato o aggiornato con successo
    if (response.ok) {
        firebase_functions_1.logger.info("OneSignal ensureUser ok", { status: response.status, data });
        return data;
    }
    // 409: utente già esistente. Aggiungi la subscription email se abbiamo un'email.
    if (response.status === 409 && email) {
        firebase_functions_1.logger.info("OneSignal user already exists, aggiungo email subscription");
        const subResponse = await fetch(`${exports.ONESIGNAL_USERS_URL}/by/external_id/${encodeURIComponent(externalId)}/subscriptions`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                Authorization: authHeader,
            },
            body: JSON.stringify({
                subscription: { type: "Email", token: email, enabled: true },
            }),
        });
        const subData = (await subResponse.json().catch(() => ({})));
        // 200/201 = creato
        if (subResponse.ok) {
            firebase_functions_1.logger.info("OneSignal email subscription ok", { status: subResponse.status });
            return { alreadyExisted: true, ...subData };
        }
        // 409 = email già presente: assicurati che sia nuovamente abilitata.
        if (subResponse.status === 409) {
            firebase_functions_1.logger.info("OneSignal email subscription already exists, la riabilito");
            const reEnableResponse = await fetch(`${exports.ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL}/Email/${encodeURIComponent(email)}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    Authorization: authHeader,
                },
                body: JSON.stringify({
                    subscription: {
                        enabled: true,
                        notification_types: 1,
                    },
                }),
            });
            const reEnableData = (await reEnableResponse.json().catch(() => ({})));
            if (reEnableResponse.ok) {
                firebase_functions_1.logger.info("OneSignal email subscription re-enabled", {
                    status: reEnableResponse.status,
                });
                return { alreadyExisted: true, reenabled: true, ...reEnableData };
            }
            firebase_functions_1.logger.error("OneSignal email subscription re-enable error", {
                status: reEnableResponse.status,
                reEnableData,
            });
            const errors = reEnableData.errors?.join(", ") ??
                "Errore riattivazione subscription";
            throw new https_1.HttpsError("internal", errors);
        }
        firebase_functions_1.logger.error("OneSignal email subscription error", { status: subResponse.status, subData });
        const errors = subData.errors?.join(", ") ?? "Errore subscription";
        throw new https_1.HttpsError("internal", errors);
    }
    firebase_functions_1.logger.error("OneSignal ensureUser error", { status: response.status, data });
    const errors = data.errors?.join(", ") ?? "Errore ensureUser";
    throw new https_1.HttpsError("internal", errors);
}
/**
 * Disabilita la subscription email OneSignal dell'utente autenticato.
 * Serve soprattutto per il percorso web, dove l'email viene registrata
 * server-side via REST API e non tramite SDK locale.
 *
 * Payload atteso dal client:
 *   { email: string }
 */
async function removeOneSignalEmailHandler(request, apiKey) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Login richiesto");
    }
    const payload = request.data;
    const email = payload?.email?.trim();
    if (!payload || typeof payload !== "object" || !email) {
        throw new https_1.HttpsError("invalid-argument", "email obbligatoria");
    }
    const externalId = request.auth.uid;
    const authHeader = `Key ${apiKey.trim()}`;
    firebase_functions_1.logger.info("OneSignal removeEmail request", {
        uid: request.auth.uid,
        externalId,
        email,
    });
    let userResponse;
    try {
        userResponse = await fetch(`${exports.ONESIGNAL_USERS_URL}/by/external_id/${encodeURIComponent(externalId)}`, {
            method: "GET",
            headers: {
                Authorization: authHeader,
            },
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("OneSignal removeEmail user lookup failed", err);
        throw new https_1.HttpsError("unavailable", "Impossibile contattare OneSignal");
    }
    const userData = (await userResponse.json().catch(() => ({})));
    if (userResponse.status === 404) {
        firebase_functions_1.logger.info("OneSignal removeEmail: utente non trovato, considero già rimosso");
        return { alreadyRemoved: true, reason: "user_not_found" };
    }
    if (!userResponse.ok) {
        firebase_functions_1.logger.error("OneSignal removeEmail user lookup error", {
            status: userResponse.status,
            userData,
        });
        const errors = userData.errors?.join(", ") ?? "Errore lookup utente";
        throw new https_1.HttpsError("internal", errors);
    }
    const subscriptions = Array.isArray(userData.subscriptions)
        ? userData.subscriptions
        : [];
    const emailSubscription = subscriptions.find((subscription) => subscription.type === "Email" && subscription.token === email);
    if (!emailSubscription || typeof emailSubscription.id !== "string") {
        firebase_functions_1.logger.info("OneSignal removeEmail: email subscription non trovata, skip", {
            externalId,
            email,
        });
        return { alreadyRemoved: true, reason: "email_not_found" };
    }
    if (emailSubscription.enabled === false) {
        firebase_functions_1.logger.info("OneSignal removeEmail: email subscription già disabilitata", {
            subscriptionId: emailSubscription.id,
        });
        return {
            alreadyRemoved: true,
            reason: "already_disabled",
            subscriptionId: emailSubscription.id,
        };
    }
    let disableResponse;
    try {
        disableResponse = await fetch(`${exports.ONESIGNAL_SUBSCRIPTIONS_URL}/${encodeURIComponent(emailSubscription.id)}`, {
            method: "PATCH",
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                Authorization: authHeader,
            },
            body: JSON.stringify({
                subscription: {
                    enabled: false,
                    notification_types: -2,
                },
            }),
        });
    }
    catch (err) {
        firebase_functions_1.logger.error("OneSignal removeEmail disable failed", err);
        throw new https_1.HttpsError("unavailable", "Impossibile contattare OneSignal");
    }
    const disableData = (await disableResponse.json().catch(() => ({})));
    if (!disableResponse.ok) {
        firebase_functions_1.logger.error("OneSignal removeEmail disable error", {
            status: disableResponse.status,
            disableData,
        });
        const errors = disableData.errors?.join(", ") ??
            "Errore disattivazione subscription";
        throw new https_1.HttpsError("internal", errors);
    }
    firebase_functions_1.logger.info("OneSignal removeEmail ok", {
        status: disableResponse.status,
        subscriptionId: emailSubscription.id,
    });
    return {
        success: true,
        subscriptionId: emailSubscription.id,
        ...disableData,
    };
}
//# sourceMappingURL=handler.js.map