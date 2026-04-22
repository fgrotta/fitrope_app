import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

export const ONESIGNAL_APP_ID = "154fc17b-3ef8-4421-a1e6-466172fa48db";
export const ONESIGNAL_API_URL = "https://api.onesignal.com/notifications";
export const ONESIGNAL_USERS_URL = `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/users`;

export interface HandlerRequest {
  auth?: { uid: string } | null;
  data: unknown;
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
export async function sendOneSignalNotificationHandler(
  request: HandlerRequest,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }

  const payload = request.data as Record<string, unknown> | null;
  if (!payload || typeof payload !== "object") {
    throw new HttpsError("invalid-argument", "Body mancante o invalido");
  }

  payload.app_id = ONESIGNAL_APP_ID;

  const logPayload = { ...payload };
  delete logPayload.email_body;
  logger.info("OneSignal request", {
    uid: request.auth.uid,
    payload: logPayload,
  });

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

  logger.info("OneSignal response", { status: response.status, data });
  return data;
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

  const externalId = payload.externalId;
  const email = payload.email?.trim();

  const body: Record<string, unknown> = {
    identity: { external_id: externalId },
  };
  if (email) {
    body.subscriptions = [
      { type: "Email", token: email, enabled: true },
    ];
  }

  logger.info("OneSignal ensureUser request", {
    uid: request.auth.uid,
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

    // 200/201 = creato, 409 = già presente: entrambi OK
    if (subResponse.ok || subResponse.status === 409) {
      logger.info("OneSignal email subscription ok", { status: subResponse.status });
      return { alreadyExisted: true, ...subData };
    }

    logger.error("OneSignal email subscription error", { status: subResponse.status, subData });
    const errors = (subData.errors as string[] | undefined)?.join(", ") ?? "Errore subscription";
    throw new HttpsError("internal", errors);
  }

  logger.error("OneSignal ensureUser error", { status: response.status, data });
  const errors = (data.errors as string[] | undefined)?.join(", ") ?? "Errore ensureUser";
  throw new HttpsError("internal", errors);
}
