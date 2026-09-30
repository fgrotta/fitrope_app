// Come parte un WhatsApp "lezione demo": un trasporto per ogni canale.
//
//   make → Custom webhook Make, che fa partire il template (makeClient.ts);
//   meta → WhatsApp Business Cloud API di Meta, direttamente (metaClient.ts).
//
// Il trasporto si sceglie con WHATSAPP_TRANSPORT (environment.ts). Tutto il
// resto — destinatario, claim nel registro, esito — resta in demoLesson.ts e
// non sa quale canale sta usando.
//
// Un trasporto non lancia mai: un invio fallito è un esito normale che cron e
// iscrizione devono poter attraversare.

import { createHash } from "crypto";
import { DemoWebhookKind } from "./payload";

export type WhatsappTransportName = "make" | "meta";

/** Parametri del template WhatsApp, già sanificati (payload.ts). */
export interface TemplateParams {
  nome: string;
  corso: string;
  giorno: string;
  orario: string;
}

export interface SendResult {
  ok: boolean;
  /** Status HTTP; `0` se manca una risposta (invio potenzialmente già accettato). */
  status: number;
  /** wamid restituito da Meta: la chiave con cui il webhook di stato riconcilia. */
  messageId?: string;
  /** `error.code` della Graph API (solo Meta). */
  errorCode?: number;
  /** `true` → rifiuto per rate limit, ritentabile nello stesso run. */
  transient?: boolean;
}

export interface WhatsappTransport {
  name: WhatsappTransportName;
  /** `false` se il canale non sa mandare questo messaggio (Meta: template non configurato). */
  supports(kind: DemoWebhookKind): boolean;
  send(kind: DemoWebhookKind, phoneE164: string, params: TemplateParams): Promise<SendResult>;
}

/** Toglie URL, chiavi e token dai messaggi d'errore prima di loggarli. */
export function scrubSecrets(message: string, secrets: string[]): string {
  let out = message;
  for (const secret of secrets) {
    if (secret) out = out.split(secret).join("[redacted]");
  }
  return out;
}

/**
 * Il wamid di Meta NON è opaco: è `wamid.` + base64 di un'intestazione e delle
 * cifre del destinatario. Nel registro si salva solo il suo SHA-256, che basta
 * a ritrovare il documento dal webhook di stato; il wamid in chiaro non va mai
 * né su Firestore né nei log.
 */
export function hashMessageId(messageId: string): string {
  return createHash("sha256").update(messageId).digest("hex");
}

/** Riferimento corto per i log: correla gli eventi senza esporre il numero. */
export function messageRef(messageId: string | undefined): string | undefined {
  return messageId ? hashMessageId(messageId).slice(0, 12) : undefined;
}
