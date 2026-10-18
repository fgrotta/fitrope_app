// Unica chiamata HTTP verso la WhatsApp Business Cloud API di Meta.
//
// `POST https://graph.facebook.com/{version}/{PHONE_NUMBER_ID}/messages` con un
// messaggio template a parametri nominati. Un 200 vuol dire "accettato", non
// "consegnato": consegna, lettura e fallimenti a valle arrivano dopo, sul
// webhook di stato (statusWebhook.ts), riconciliati col wamid restituito qui.
//
// Non lancia mai, come postToMake. Gli errori sincroni si classificano sul
// `error.code` della Graph API, non sullo status HTTP: solo 130429 (rate limit
// del numero) si ritenta nello stesso run; 131056 (troppi messaggi alla stessa
// persona) e tutti gli altri sono rifiuti. Il token viaggia solo nell'header e
// non compare mai nei log, come il numero del destinatario e il wamid, che lo
// contiene (transport.ts, hashMessageId).

import { logger } from "firebase-functions";
import { DemoWebhookKind } from "./payload";
import {
  SendResult,
  TemplateParams,
  WhatsappTransport,
  messageRef,
  scrubSecrets,
} from "./transport";

const GRAPH_BASE_URL = "https://graph.facebook.com";

/** Come per Make: undici non ha un timeout breve di default. */
const DEFAULT_TIMEOUT_MS = 10_000;

/** Rate limit del numero mittente: l'unico errore ritentabile subito. */
const TRANSIENT_ERROR_CODES = new Set([130429]);

/** Token scaduto o revocato: falliscono TUTTI gli invii finché non si ruota il secret. */
const INVALID_TOKEN_CODE = 190;

/** Messaggio fisso, su cui agganciare un alert Cloud Logging. */
export const META_CREDENTIALS_REJECTED_LOG =
  "Credenziali Meta rifiutate (code 190): ruotare META_WA_ACCESS_TOKEN e ridistribuire";

export interface MetaTemplateRef {
  name: string;
  /** Codice lingua del template approvato, es. `it`. */
  lang: string;
}

export interface MetaConfig {
  /** Versione Graph API, es. `v26.0`: ogni versione vive circa due anni. */
  graphVersion: string;
  /** Id del numero mittente sulla WABA (non è il numero di telefono). */
  phoneNumberId: string;
  accessToken: string;
  /** Un template per kind: un kind senza template non è inviabile via Meta. */
  templates: Partial<Record<DemoWebhookKind, MetaTemplateRef>>;
}

interface GraphError {
  message?: string;
  type?: string;
  code?: number;
  error_subcode?: number;
  error_data?: { details?: string };
  fbtrace_id?: string;
}

/** Body del messaggio template. `to` vuole le cifre E.164 senza `+`. */
export function buildMetaTemplateBody(
  phoneE164: string,
  template: MetaTemplateRef,
  params: TemplateParams
): Record<string, unknown> {
  const named = (key: keyof TemplateParams) => ({
    type: "text",
    parameter_name: key,
    text: params[key],
  });
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: phoneE164.replace(/^\+/, ""),
    type: "template",
    template: {
      name: template.name,
      language: { code: template.lang },
      components: [
        {
          type: "body",
          parameters: [named("nome"), named("corso"), named("giorno"), named("orario")],
        },
      ],
    },
  };
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** Numero in tutte le forme in cui Meta può rimandarlo nei messaggi d'errore. */
function phoneForms(phoneE164: string): string[] {
  const digits = phoneE164.replace(/^\+/, "");
  const national = digits.startsWith("39") ? digits.slice(2) : digits;
  return [phoneE164, digits, national];
}

export async function postToMeta(
  config: MetaConfig,
  kind: DemoWebhookKind,
  phoneE164: string,
  params: TemplateParams,
  opts: { timeoutMs?: number } = {}
): Promise<SendResult> {
  const template = config.templates[kind];
  if (!template) {
    logger.error("Nessun template Meta configurato per questo messaggio", { kind });
    return { ok: false, status: 0 };
  }

  // Un secret caricato con `secrets:set --data-file` può portarsi dietro il newline.
  const accessToken = config.accessToken.trim();
  const secrets = [accessToken, ...phoneForms(phoneE164)];
  const url = `${GRAPH_BASE_URL}/${config.graphVersion}/${config.phoneNumberId}/messages`;
  let response: Awaited<ReturnType<typeof fetch>>;
  let text: string;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(buildMetaTemplateBody(phoneE164, template, params)),
      signal: AbortSignal.timeout(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
    text = await response.text();
  } catch (err) {
    logger.error("Chiamata alla Cloud API Meta fallita", {
      kind,
      template: template.name,
      error: scrubSecrets(err instanceof Error ? err.message : String(err), secrets),
    });
    return { ok: false, status: 0 };
  }

  const body = parseJson(text) as {
    messages?: Array<{ id?: string; message_status?: string }>;
    error?: GraphError;
  } | null;

  if (response.ok) {
    const message = body?.messages?.[0];
    const messageId = typeof message?.id === "string" && message.id !== "" ? message.id : undefined;
    if (!messageId) {
      logger.warn("Cloud API Meta: 2xx senza wamid, esito di consegna non riconciliabile", {
        kind,
        status: response.status,
      });
    }
    logger.info("Messaggio WhatsApp accettato da Meta", {
      kind,
      template: template.name,
      status: response.status,
      messageStatus: message?.message_status,
      messageRef: messageRef(messageId),
    });
    return { ok: true, status: response.status, ...(messageId ? { messageId } : {}) };
  }

  const error = body?.error;
  const errorCode = typeof error?.code === "number" ? error.code : undefined;
  const logFields = {
    kind,
    template: template.name,
    status: response.status,
    code: errorCode,
    subcode: error?.error_subcode,
    type: error?.type,
    fbtraceId: error?.fbtrace_id,
    message: scrubSecrets(error?.message ?? "", secrets),
    details: scrubSecrets(error?.error_data?.details ?? "", secrets),
  };
  if (errorCode === INVALID_TOKEN_CODE) {
    logger.error(META_CREDENTIALS_REJECTED_LOG, logFields);
  } else {
    logger.error("Cloud API Meta ha rifiutato il messaggio", logFields);
  }

  return {
    ok: false,
    status: response.status,
    ...(errorCode !== undefined ? { errorCode } : {}),
    transient: errorCode !== undefined && TRANSIENT_ERROR_CODES.has(errorCode),
  };
}

export function metaTransport(config: MetaConfig): WhatsappTransport {
  return {
    name: "meta",
    supports: (kind) => config.templates[kind] !== undefined,
    send: (kind, phoneE164, params) => postToMeta(config, kind, phoneE164, params),
  };
}
