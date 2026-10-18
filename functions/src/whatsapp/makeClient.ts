// Unica chiamata HTTP verso il Custom webhook Make.
//
// Non lancia mai: un invio fallito è un esito normale che cron e iscrizione
// devono poter attraversare. Non deserializza la risposta: Make risponde
// "Accepted" in testo, e gli errori a valle (numero non su WhatsApp, template
// non approvato, credito esaurito) non tornano comunque indietro.

import { logger } from "firebase-functions";
import { DemoLessonPayload, toMakeBody } from "./payload";
import { WhatsappTransport, scrubSecrets } from "./transport";

/** Header su cui lo scenario Make filtra le richieste. */
export const MAKE_AUTH_HEADER = "Demo-Reminder";

/**
 * undici (il fetch di Node) non ha un timeout breve di default: senza questo
 * uno scenario appeso bloccherebbe cron e iscrizione per minuti.
 */
const DEFAULT_TIMEOUT_MS = 10_000;

export interface PostResult {
  ok: boolean;
  /** Status HTTP; `0` se manca una risposta (invio potenzialmente già accettato). */
  status: number;
}

/** Solo l'host: l'URL completo contiene il token del webhook. */
function safeHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return "unknown";
  }
}

export async function postToMake(
  url: string,
  apiKey: string,
  payload: DemoLessonPayload,
  opts: { timeoutMs?: number } = {}
): Promise<PostResult> {
  const host = safeHost(url);
  let response: Awaited<ReturnType<typeof fetch>>;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [MAKE_AUTH_HEADER]: apiKey,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
  } catch (err) {
    logger.error("Chiamata al webhook Make fallita", {
      host,
      tipo: payload.tipo,
      error: scrubSecrets(err instanceof Error ? err.message : String(err), [url, apiKey]),
    });
    return { ok: false, status: 0 };
  }

  if (!response.ok) {
    logger.error("Webhook Make ha risposto con errore", {
      host,
      status: response.status,
      tipo: payload.tipo,
    });
    return { ok: false, status: response.status };
  }

  logger.info("Webhook Make chiamato", { host, status: response.status, tipo: payload.tipo });
  return { ok: true, status: response.status };
}

/**
 * Trasporto Make: il body del contratto (payload.ts) e la chiave nell'header.
 * Make sa mandare entrambi i messaggi, perché il Router dello scenario sceglie
 * il template dal campo `tipo`. HTTP 429 è l'unico rifiuto ritentabile.
 */
export function makeTransport(url: string, apiKey: string): WhatsappTransport {
  return {
    name: "make",
    supports: () => true,
    send: async (kind, phoneE164, params) => {
      const result = await postToMake(url, apiKey, toMakeBody(kind, phoneE164, params));
      return result.ok ? result : { ...result, transient: result.status === 429 };
    },
  };
}
