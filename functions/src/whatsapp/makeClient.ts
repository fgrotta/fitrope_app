// Unica chiamata HTTP verso il Custom webhook Make. L'URL è l'unica
// credenziale: lo scenario non filtra su header, quindi chi lo conosce può
// far partire un WhatsApp. Per questo non compare mai nei log (solo l'host).
//
// Non lancia mai: un invio fallito è un esito normale che cron e iscrizione
// devono poter attraversare. Non deserializza la risposta: Make risponde
// "Accepted" in testo, e gli errori a valle (numero non su WhatsApp, template
// non approvato, credito esaurito) non tornano comunque indietro.

import { logger } from "firebase-functions";
import { DemoLessonPayload } from "./payload";

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

function scrubSecrets(message: string, secrets: string[]): string {
  let out = message;
  for (const secret of secrets) {
    if (secret) out = out.split(secret).join("[redacted]");
  }
  return out;
}

export async function postToMake(
  url: string,
  payload: DemoLessonPayload,
  opts: { timeoutMs?: number } = {}
): Promise<PostResult> {
  const host = safeHost(url);
  let response: Awaited<ReturnType<typeof fetch>>;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
  } catch (err) {
    logger.error("Chiamata al webhook Make fallita", {
      host,
      error: scrubSecrets(err instanceof Error ? err.message : String(err), [url]),
    });
    return { ok: false, status: 0 };
  }

  if (!response.ok) {
    logger.error("Webhook Make ha risposto con errore", {
      host,
      status: response.status,
    });
    return { ok: false, status: response.status };
  }

  logger.info("Webhook Make chiamato", { host, status: response.status });
  return { ok: true, status: response.status };
}
