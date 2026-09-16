// Helper condivisi per le push OneSignal server-side.
//
// Sta nella root di `src/` perché serve sia ai flussi di iscrizione
// (`enrollment/notify.ts`) sia al cron dei certificati (`certificateEmails.ts`).
//
// Il deeplink usa il campo `web_url` e non `url`/`app_url`: l'app Flutter non
// registra uno schema custom, quindi l'unico target valido è l'URL web.

import { logger } from "firebase-functions";
import { ONESIGNAL_APP_ID, postToOneSignal } from "./handler";

const FALLBACK_PROJECT_ID = "fit-rope-app-1f575";
const PROD_APP_BASE_URL = "https://app.fithousemonza.it/";
const STAGING_APP_BASE_URL = "https://fgrotta.github.io/fitrope_app/";

const APP_BASE_URL_BY_PROJECT: Record<string, string> = {
  "fit-rope-app-1f575": PROD_APP_BASE_URL,
  "fit-rope-staging": STAGING_APP_BASE_URL,
};

function projectId(): string {
  return (
    process.env.GCLOUD_PROJECT ??
    process.env.GOOGLE_CLOUD_PROJECT ??
    FALLBACK_PROJECT_ID
  );
}

/**
 * Base URL della PWA, risolta a runtime: prod e staging producono ognuno il
 * proprio link senza configurazione aggiuntiva. Stesso pattern di
 * `icsBaseUrl()`; `APP_BASE_URL` permette l'override.
 */
export function appBaseUrl(): string {
  const override = process.env.APP_BASE_URL?.trim();
  if (override) return override.endsWith("/") ? override : `${override}/`;

  const project = projectId();
  const mapped = APP_BASE_URL_BY_PROJECT[project];
  if (mapped) return mapped;

  logger.warn("appBaseUrl: progetto sconosciuto, uso il base URL di produzione", {
    project,
  });
  return PROD_APP_BASE_URL;
}

/**
 * URL di apertura della push. Punta alla **root**, non a `#/protected`: con la
 * strategia hash un fragment non vuoto ha la precedenza su `initialRoute`
 * (`SPLASH_ROUTE`) e si salterebbe lo splash, cioè restore auth, preload dei
 * chunk deferred e init OneSignal. `?src=` serve solo a misurare quale evento
 * ha portato l'utente dentro.
 */
export function pushLaunchUrl(source?: string): string {
  const base = appBaseUrl();
  return source ? `${base}?src=${encodeURIComponent(source)}` : base;
}

export interface PushPayloadArgs {
  /** Destinatari come alias OneSignal (= uid Firestore). */
  externalIds: string[];
  heading: string;
  content: string;
  /** Default: la versione italiana (meglio ripetuta che assente). */
  headingEn?: string;
  contentEn?: string;
  /** Finisce in `?src=` del deeplink. */
  source?: string;
  /** ISO 8601, per gli invii schedulati. */
  sendAfter?: string;
  /** Secondi di vita della notifica: oltre, OneSignal non la consegna più. */
  ttlSeconds?: number;
  /** Notifiche con lo stesso id si sostituiscono invece di accumularsi. */
  collapseId?: string;
}

/**
 * Costruisce il payload push. Pura, e inietta `app_id` come fa
 * `buildCertificateEmailPayload`: il percorso schedulato chiama
 * `postToOneSignal` direttamente, che non lo inietta.
 */
export function buildPushPayload(args: PushPayloadArgs): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: { external_id: args.externalIds },
    target_channel: "push",
    headings: { it: args.heading, en: args.headingEn ?? args.heading },
    contents: { it: args.content, en: args.contentEn ?? args.content },
    web_url: pushLaunchUrl(args.source),
  };
  if (args.sendAfter) payload.send_after = args.sendAfter;
  if (args.ttlSeconds !== undefined) payload.ttl = args.ttlSeconds;
  if (args.collapseId) payload.collapse_id = args.collapseId;
  return payload;
}

/**
 * Invio best-effort: una push mancata non deve mai far fallire l'operazione che
 * l'ha generata (un'iscrizione, un run del cron).
 */
export async function sendPush(
  apiKey: string,
  label: string,
  args: PushPayloadArgs
): Promise<void> {
  try {
    await postToOneSignal(buildPushPayload(args), apiKey);
  } catch (err) {
    logger.warn(`OneSignal ${label} errore`, err);
  }
}
