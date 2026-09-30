// Webhook di stato della WhatsApp Cloud API (export `whatsappStatusWebhook`).
//
// Meta chiama questo endpoint in due modi:
//   GET  → verifica dell'URL al salvataggio in console: se `hub.verify_token`
//          coincide con META_WA_VERIFY_TOKEN si risponde `hub.challenge` in chiaro;
//   POST → eventi del campo `messages`, firmati con
//          `X-Hub-Signature-256: sha256=<HMAC-SHA256(corpo grezzo, META_APP_SECRET)>`.
//
// Dei POST si usano solo gli stati (`value.statuses[]`): sent, delivered,
// read, failed, riconciliati sul registro dal wamid (sendLog.ts). Sullo stesso
// endpoint arrivano anche i messaggi degli utenti (`value.messages[]`): si
// accettano e si ignorano, senza salvarne né loggarne il contenuto. Non si
// salva mai `recipient_id`, che è il telefono del destinatario.
//
// Dopo una firma valida si risponde SEMPRE 200, anche se Firestore fallisce:
// un 5xx fa ritentare Meta per giorni e alla lunga disattiva la sottoscrizione.
// La function è pubblica per necessità; la protezione è la firma.

import { createHash, createHmac, timingSafeEqual } from "crypto";
import { logger } from "firebase-functions";
import type { Firestore } from "firebase-admin/firestore";
import { applyDeliveryStatus, isDeliveryStatus } from "./sendLog";

/** Nome dell'header come lo espone Express (minuscolo). */
export const SIGNATURE_HEADER = "x-hub-signature-256";

export interface StatusWebhookRequest {
  method: string;
  query: Record<string, unknown>;
  headers: Record<string, string | string[] | undefined>;
  /** Corpo grezzo: la firma è calcolata sui byte, non sul JSON riserializzato. */
  rawBody?: Buffer;
}

export interface StatusWebhookResponse {
  status: number;
  body: string;
}

export interface StatusWebhookDeps {
  db: Firestore;
  appSecret: string;
  verifyToken: string;
}

interface MetaStatus {
  id?: unknown;
  status?: unknown;
  timestamp?: unknown;
  errors?: Array<{ code?: unknown; title?: unknown }>;
  pricing?: { category?: unknown; billable?: unknown };
}

interface MetaWebhookBody {
  entry?: Array<{
    changes?: Array<{
      field?: unknown;
      value?: { statuses?: MetaStatus[]; messages?: unknown[] };
    }>;
  }>;
}

/** Confronto a tempo costante anche fra stringhe di lunghezza diversa. */
function safeEqual(a: string, b: string): boolean {
  const digest = (value: string) => createHash("sha256").update(value).digest();
  return timingSafeEqual(digest(a), digest(b));
}

function headerValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export function verifySignature(
  rawBody: Buffer | undefined,
  header: string | undefined,
  appSecret: string
): boolean {
  if (!rawBody || !header || !appSecret || !header.startsWith("sha256=")) return false;
  const expected = `sha256=${createHmac("sha256", appSecret).update(rawBody).digest("hex")}`;
  return safeEqual(header, expected);
}

function handleVerification(req: StatusWebhookRequest, deps: StatusWebhookDeps): StatusWebhookResponse {
  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];
  if (
    mode === "subscribe" &&
    typeof token === "string" &&
    typeof challenge === "string" &&
    deps.verifyToken !== "" &&
    safeEqual(token, deps.verifyToken)
  ) {
    logger.info("Webhook WhatsApp verificato da Meta");
    return { status: 200, body: challenge };
  }
  logger.warn("Verifica webhook WhatsApp rifiutata", { mode: typeof mode === "string" ? mode : undefined });
  return { status: 403, body: "Forbidden" };
}

function parseBody(raw: Buffer): MetaWebhookBody | null {
  try {
    const parsed = JSON.parse(raw.toString("utf8")) as unknown;
    return parsed && typeof parsed === "object" ? (parsed as MetaWebhookBody) : null;
  } catch {
    return null;
  }
}

async function applyStatus(db: Firestore, status: MetaStatus): Promise<void> {
  const messageId = typeof status.id === "string" ? status.id : "";
  if (messageId === "" || !isDeliveryStatus(status.status)) {
    logger.info("Stato WhatsApp ignorato", { status: String(status.status) });
    return;
  }
  const seconds = Number(status.timestamp);
  const timestampMillis = Number.isFinite(seconds) && seconds > 0 ? seconds * 1000 : Date.now();
  const first = status.errors?.[0];
  const error =
    first === undefined
      ? undefined
      : {
          code: typeof first.code === "number" ? first.code : undefined,
          title: typeof first.title === "string" ? first.title : undefined,
        };

  // Per la prima settimana: verificare che Meta non abbia riclassificato il
  // template in Marketing (costi e limiti diversi).
  if (status.pricing?.category !== undefined) {
    logger.info("Categoria di prezzo WhatsApp", {
      messageId,
      category: String(status.pricing.category),
      billable: status.pricing.billable === true,
    });
  }

  try {
    const result = await applyDeliveryStatus(db, messageId, status.status, timestampMillis, error);
    if (result === "not_found") {
      // Tipico dei messaggi di prova mandati dal WhatsApp Manager.
      logger.info("Stato WhatsApp per un wamid sconosciuto", { messageId, status: status.status });
    } else if (status.status === "failed") {
      logger.warn("WhatsApp non consegnato", { messageId, errorCode: error?.code, errorTitle: error?.title });
    }
  } catch (err) {
    logger.error("Stato WhatsApp non registrato", {
      messageId,
      status: status.status,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

export async function handleStatusWebhook(
  req: StatusWebhookRequest,
  deps: StatusWebhookDeps
): Promise<StatusWebhookResponse> {
  if (req.method === "GET") return handleVerification(req, deps);
  if (req.method !== "POST") return { status: 405, body: "Method Not Allowed" };

  if (!verifySignature(req.rawBody, headerValue(req.headers[SIGNATURE_HEADER]), deps.appSecret)) {
    logger.warn("Webhook WhatsApp: firma assente o non valida");
    return { status: 401, body: "Unauthorized" };
  }

  const body = parseBody(req.rawBody as Buffer);
  if (body === null) {
    logger.warn("Webhook WhatsApp: corpo firmato ma non JSON");
    return { status: 200, body: "EVENT_RECEIVED" };
  }

  let inbound = 0;
  for (const entry of body.entry ?? []) {
    for (const change of entry.changes ?? []) {
      if (change.field !== "messages") continue;
      inbound += change.value?.messages?.length ?? 0;
      // In ordine: ogni stato si applica solo se fa avanzare quello salvato.
      for (const status of change.value?.statuses ?? []) {
        await applyStatus(deps.db, status);
      }
    }
  }
  if (inbound > 0) logger.info("Messaggi WhatsApp in ingresso ignorati", { count: inbound });
  return { status: 200, body: "EVENT_RECEIVED" };
}
