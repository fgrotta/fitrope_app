import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import type { Firestore } from "firebase-admin/firestore";

export const ONESIGNAL_APP_ID =
  process.env.ONESIGNAL_APP_ID ?? "154fc17b-3ef8-4421-a1e6-466172fa48db";
export const ONESIGNAL_API_URL = "https://api.onesignal.com/notifications";
export const ONESIGNAL_USERS_URL = `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/users`;
export const ONESIGNAL_SUBSCRIPTIONS_URL = `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/subscriptions`;
export const ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL =
  `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/subscriptions_by_token`;

const STAGING_EXTERNAL_ID_PREFIX = "stg_";

function isStagingEnvironment(): boolean {
  return process.env.APP_ENV === "staging";
}

export function isStagingIdentityAllowed(externalId: string, email?: string): boolean {
  if (!isStagingEnvironment()) return true;

  const allowedEmails = new Set(
    (process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST ?? "")
      .split(",")
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean)
  );
  const normalizedEmail = email?.trim().toLowerCase();
  return externalId.startsWith(STAGING_EXTERNAL_ID_PREFIX) &&
    !!normalizedEmail && allowedEmails.has(normalizedEmail);
}

function isStagingNotificationAllowed(payload: Record<string, unknown>): boolean {
  if (!isStagingEnvironment()) return true;

  const aliases = payload.include_aliases as { external_id?: unknown } | undefined;
  const externalIds = Array.isArray(aliases?.external_id)
    ? aliases.external_id.filter((id): id is string => typeof id === "string")
    : [];
  return externalIds.length > 0 &&
    externalIds.every((externalId) => externalId.startsWith(STAGING_EXTERNAL_ID_PREFIX));
}

function markStagingNotification(payload: Record<string, unknown>): void {
  if (!isStagingEnvironment()) return;

  if (typeof payload.email_subject === "string") {
    payload.email_subject = `[STAGING] ${payload.email_subject}`;
  }
  if (payload.contents && typeof payload.contents === "object") {
    const contents = payload.contents as Record<string, unknown>;
    for (const [locale, value] of Object.entries(contents)) {
      if (typeof value === "string") contents[locale] = `[STAGING] ${value}`;
    }
  }
}

export interface HandlerRequest {
  auth?: { uid: string } | null;
  data: unknown;
}

/**
 * Esegue la POST verso OneSignal e gestisce la risposta.
 * Condivisa tra l'handler onCall e le funzioni schedulate (che non hanno auth).
 * Il chiamante deve aver già iniettato `app_id` nel payload.
 */
export async function postToOneSignal(
  payload: Record<string, unknown>,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (payload.target_channel === "push" && isStagingEnvironment()) {
    logger.warn("OneSignal push notification suppressed in staging");
    return { suppressed: true };
  }
  if (!isStagingNotificationAllowed(payload)) {
    logger.warn("OneSignal notification suppressed in staging", {
      include_aliases: payload.include_aliases,
    });
    return { suppressed: true };
  }
  markStagingNotification(payload);

  let response: Response;
  try {
    response = await fetch(ONESIGNAL_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: `Key ${apiKey.trim()}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    logger.error("OneSignal fetch failed", err);
    throw new HttpsError("unavailable", "Impossibile contattare OneSignal");
  }

  const data = (await response.json()) as Record<string, unknown>;

  if (!response.ok) {
    logger.error("OneSignal error", { status: response.status, data });
    const errors = (data.errors as string[] | undefined)?.join(", ") ?? "Errore OneSignal";
    throw new HttpsError("internal", errors);
  }

  // OneSignal può rispondere 200 con errori nel body (es. invalid_aliases) o
  // con recipients: 0 (nessun destinatario raggiunto): sono fallimenti
  // silenziosi da rendere visibili nei log.
  if (data.errors) {
    logger.warn("OneSignal 200 ma con errors nel body (possibile invio parziale)", { data });
  }
  if (data.recipients === 0) {
    logger.warn("OneSignal 200 ma recipients: 0 (nessun destinatario raggiunto)", { data });
  }

  logger.info("OneSignal response", { status: response.status, data });
  return data;
}

/**
 * Dipendenze iniettate nell'handler di invio (pattern come RunDeps in
 * certificateEmails.ts): permettono ai test di usare un db/ensure finti
 * senza inizializzare firebase-admin.
 */
export interface SendNotificationDeps {
  db: Firestore;
  ensure: (
    externalId: string,
    email: string | undefined,
    apiKey: string
  ) => Promise<unknown>;
}

/**
 * Garantisce che ogni destinatario email esista su OneSignal prima dell'invio:
 * legge l'email da Firestore (users/{uid}, doc-id == uid) e chiama l'ensure
 * idempotente. Un external_id mai creato su OneSignal produrrebbe un invio
 * "riuscito" (200) ma con recipients: 0 per quell'utente.
 *
 * Best-effort: nessun errore per-utente blocca gli altri destinatari o
 * l'invio; ogni anomalia viene loggata (visibile con `firebase functions:log`).
 */
export async function ensureEmailRecipientsFromFirestore(
  externalIds: string[],
  deps: SendNotificationDeps,
  apiKey: string
): Promise<string[]> {
  const uniqueIds = [...new Set(externalIds)];
  const recipients = await Promise.all(
    uniqueIds.map(async (externalId): Promise<string | null> => {
      try {
        const snapshot = await deps.db.collection("users").doc(externalId).get();
        if (!snapshot.exists) {
          logger.warn("Ensure destinatario: utente non trovato su Firestore, invio comunque", {
            externalId,
          });
          return isStagingEnvironment() ? null : externalId;
        }
        // Stessa semantica di _hasUsableEmail lato Dart: - è il placeholder
        // per gli utenti senza email.
        const email = (snapshot.data()?.email as string | undefined)?.trim();
        if (!email || email === "-") {
          logger.warn("Ensure destinatario: email non usabile su Firestore, invio comunque", {
            externalId,
          });
          return isStagingEnvironment() ? null : externalId;
        }
        if (!isStagingIdentityAllowed(externalId, email)) {
          logger.warn("Ensure destinatario soppresso in staging", { externalId });
          return null;
        }
        await deps.ensure(externalId, email, apiKey);
        return externalId;
      } catch (err) {
        logger.warn("Ensure destinatario fallito, invio comunque", { externalId, err });
        return isStagingEnvironment() ? null : externalId;
      }
    })
  );
  return recipients.filter((externalId): externalId is string => externalId !== null);
}

/**
 * Logica di inoltro verso OneSignal REST API.
 * Esposta separatamente da `onCall` per poter essere testata senza dipendere
 * dall'infrastruttura Firebase Functions.
 *
 * - Verifica autenticazione
 * - Verifica payload
 * - Inietta app_id server-side
 * - Per gli invii email mirati, garantisce i destinatari su OneSignal
 * - Chiama OneSignal con la REST API key (passata come parametro)
 */
export async function sendOneSignalNotificationHandler(
  request: HandlerRequest,
  apiKey: string,
  deps: SendNotificationDeps
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as Record<string, unknown> | null;
  if (!payload || typeof payload !== "object") {
    throw new HttpsError("invalid-argument", "Body mancante o invalido");
  }

  payload.app_id = ONESIGNAL_APP_ID;

  const aliases = payload.include_aliases as { external_id?: unknown } | undefined;
  const externalIds = Array.isArray(aliases?.external_id)
    ? aliases.external_id.filter(
        (id): id is string => typeof id === "string" && id.length > 0
      )
    : [];
  if (payload.target_channel === "email" && externalIds.length > 0) {
    const recipients = await ensureEmailRecipientsFromFirestore(externalIds, deps, apiKey);
    if (isStagingEnvironment() && aliases) aliases.external_id = recipients;
  }

  const logPayload = { ...payload };
  delete logPayload.email_body;
  logger.info("OneSignal request", {
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
export async function ensureOneSignalUserHandler(
  request: HandlerRequest,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as { externalId?: string; email?: string } | null;
  if (!payload || typeof payload !== "object" || !payload.externalId) {
    throw new HttpsError("invalid-argument", "externalId obbligatorio");
  }

  return ensureOneSignalEmailSubscription(
    payload.externalId,
    payload.email?.trim(),
    apiKey
  );
}

/**
 * Crea/aggiorna la subscription email OneSignal per un external_id.
 * Estratta dall'handler onCall per essere riusata dalla Cloud Function
 * schedulata (che non ha contesto auth). Idempotente: se l'utente esiste già
 * (409) aggiunge l'email; se l'email esiste ma è disabilitata, la riabilita.
 * È la stessa logica usata al login.
 */
export async function ensureOneSignalEmailSubscription(
  externalId: string,
  email: string | undefined,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (!isStagingIdentityAllowed(externalId, email)) {
    logger.warn("OneSignal identity suppressed in staging", { externalId });
    return { suppressed: true };
  }

  const body: Record<string, unknown> = {
    identity: { external_id: externalId },
  };
  if (email) {
    body.subscriptions = [
      { type: "Email", token: email, enabled: true },
    ];
  }

  logger.info("OneSignal ensureUser request", {
    externalId,
    hasEmail: !!email,
  });

  const authHeader = `Key ${apiKey.trim()}`;
  let response: Response;
  try {
    response = await fetch(ONESIGNAL_USERS_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: authHeader,
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    logger.error("OneSignal ensureUser fetch failed", err);
    throw new HttpsError("unavailable", "Impossibile contattare OneSignal");
  }

  const data = (await response.json().catch(() => ({}))) as Record<string, unknown>;

  // 200/201: creato o aggiornato con successo
  if (response.ok) {
    logger.info("OneSignal ensureUser ok", { status: response.status, data });
    return data;
  }

  // 409: utente già esistente. Aggiungi la subscription email se abbiamo un'email.
  if (response.status === 409 && email) {
    logger.info("OneSignal user already exists, aggiungo email subscription");
    const subResponse = await fetch(
      `${ONESIGNAL_USERS_URL}/by/external_id/${encodeURIComponent(externalId)}/subscriptions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          Authorization: authHeader,
        },
        body: JSON.stringify({
          subscription: { type: "Email", token: email, enabled: true },
        }),
      }
    );
    const subData = (await subResponse.json().catch(() => ({}))) as Record<string, unknown>;

    // 200/201 = creato
    if (subResponse.ok) {
      logger.info("OneSignal email subscription ok", { status: subResponse.status });
      return { alreadyExisted: true, ...subData };
    }

    // 409 = email già presente: assicurati che sia nuovamente abilitata.
    if (subResponse.status === 409) {
      logger.info("OneSignal email subscription already exists, la riabilito");
      const reEnableResponse = await fetch(
        `${ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL}/Email/${encodeURIComponent(email)}`,
        {
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
        }
      );
      const reEnableData =
        (await reEnableResponse.json().catch(() => ({}))) as Record<string, unknown>;

      if (reEnableResponse.ok) {
        logger.info("OneSignal email subscription re-enabled", {
          status: reEnableResponse.status,
        });
        return { alreadyExisted: true, reenabled: true, ...reEnableData };
      }

      logger.error("OneSignal email subscription re-enable error", {
        status: reEnableResponse.status,
        reEnableData,
      });
      const errors =
        (reEnableData.errors as string[] | undefined)?.join(", ") ??
        "Errore riattivazione subscription";
      throw new HttpsError("internal", errors);
    }

    logger.error("OneSignal email subscription error", { status: subResponse.status, subData });
    const errors = (subData.errors as string[] | undefined)?.join(", ") ?? "Errore subscription";
    throw new HttpsError("internal", errors);
  }

  logger.error("OneSignal ensureUser error", { status: response.status, data });
  const errors = (data.errors as string[] | undefined)?.join(", ") ?? "Errore ensureUser";
  throw new HttpsError("internal", errors);
}

/**
 * Disabilita la subscription email OneSignal dell'utente autenticato.
 * Serve soprattutto per il percorso web, dove l'email viene registrata
 * server-side via REST API e non tramite SDK locale.
 *
 * Payload atteso dal client:
 *   { email: string }
 */
export async function removeOneSignalEmailHandler(
  request: HandlerRequest,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as { email?: string } | null;
  const email = payload?.email?.trim();
  if (!payload || typeof payload !== "object" || !email) {
    throw new HttpsError("invalid-argument", "email obbligatoria");
  }

  const externalId = request.auth.uid;
  if (!isStagingIdentityAllowed(externalId, email)) {
    logger.warn("OneSignal email removal suppressed in staging", { externalId });
    return { suppressed: true };
  }

  const authHeader = `Key ${apiKey.trim()}`;

  logger.info("OneSignal removeEmail request", {
    uid: request.auth.uid,
    externalId,
    email,
  });

  let userResponse: Response;
  try {
    userResponse = await fetch(
      `${ONESIGNAL_USERS_URL}/by/external_id/${encodeURIComponent(externalId)}`,
      {
        method: "GET",
        headers: {
          Authorization: authHeader,
        },
      }
    );
  } catch (err) {
    logger.error("OneSignal removeEmail user lookup failed", err);
    throw new HttpsError("unavailable", "Impossibile contattare OneSignal");
  }

  const userData = (await userResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (userResponse.status === 404) {
    logger.info("OneSignal removeEmail: utente non trovato, considero già rimosso");
    return { alreadyRemoved: true, reason: "user_not_found" };
  }
  if (!userResponse.ok) {
    logger.error("OneSignal removeEmail user lookup error", {
      status: userResponse.status,
      userData,
    });
    const errors =
      (userData.errors as string[] | undefined)?.join(", ") ?? "Errore lookup utente";
    throw new HttpsError("internal", errors);
  }

  const subscriptions = Array.isArray(userData.subscriptions)
    ? (userData.subscriptions as Record<string, unknown>[])
    : [];
  const emailSubscription = subscriptions.find((subscription) =>
    subscription.type === "Email" && subscription.token === email
  );

  if (!emailSubscription || typeof emailSubscription.id !== "string") {
    logger.info("OneSignal removeEmail: email subscription non trovata, skip", {
      externalId,
      email,
    });
    return { alreadyRemoved: true, reason: "email_not_found" };
  }

  if (emailSubscription.enabled === false) {
    logger.info("OneSignal removeEmail: email subscription già disabilitata", {
      subscriptionId: emailSubscription.id,
    });
    return {
      alreadyRemoved: true,
      reason: "already_disabled",
      subscriptionId: emailSubscription.id,
    };
  }

  let disableResponse: Response;
  try {
    disableResponse = await fetch(
      `${ONESIGNAL_SUBSCRIPTIONS_URL}/${encodeURIComponent(emailSubscription.id)}`,
      {
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
      }
    );
  } catch (err) {
    logger.error("OneSignal removeEmail disable failed", err);
    throw new HttpsError("unavailable", "Impossibile contattare OneSignal");
  }

  const disableData =
    (await disableResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!disableResponse.ok) {
    logger.error("OneSignal removeEmail disable error", {
      status: disableResponse.status,
      disableData,
    });
    const errors =
      (disableData.errors as string[] | undefined)?.join(", ") ??
      "Errore disattivazione subscription";
    throw new HttpsError("internal", errors);
  }

  logger.info("OneSignal removeEmail ok", {
    status: disableResponse.status,
    subscriptionId: emailSubscription.id,
  });
  return {
    success: true,
    subscriptionId: emailSubscription.id,
    ...disableData,
  };
}
