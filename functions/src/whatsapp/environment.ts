// Cosa esiste e a chi si può scrivere, in base all'ambiente.
//
// WHATSAPP_DEMO_MODE (in `.env.<projectId>`, letta dalla CLI prima della
// discovery degli export, come i gate dei certificati in index.ts):
//   off  (default, e per qualunque valore sconosciuto) → niente WhatsApp;
//   test → solo la callable di prova (Admin), per verificare lo scenario Make;
//   live → + conferma all'iscrizione + cron dei promemoria.
//
// WHATSAPP_TRANSPORT sceglie il canale (transport.ts): `make` (default, anche
// se assente: comportamento di sempre) o `meta` (Cloud API diretta). Con `meta`
// la discovery legge anche la configurazione non segreta del numero e dei
// template, e fallisce subito se manca: meglio un deploy rotto che un cron che
// scopre l'errore alle 19:00.
//
// Su staging i dati possono essere un clone della produzione, con numeri reali:
// lì un numero passa solo se è in STAGING_WHATSAPP_ALLOWLIST (lista separata da
// virgole, anche senza prefisso: viene normalizzata). Stessa regola
// sull'emulatore: parte con `--project fit-rope-app-1f575`, quindi eredita la
// modalità della produzione, legge i secret Make da Secret Manager se mancano
// in `.secret.local` e può contenere un export dei dati reali.

import type { MetaConfig } from "./metaClient";
import { normalizePhoneE164 } from "./phone";
import type { WhatsappTransportName } from "./transport";

export type WhatsappDemoMode = "off" | "test" | "live";

export function whatsappDemoMode(env: NodeJS.ProcessEnv): WhatsappDemoMode {
  const raw = (env.WHATSAPP_DEMO_MODE ?? "").trim().toLowerCase();
  return raw === "test" || raw === "live" ? raw : "off";
}

export function whatsappTransportName(env: NodeJS.ProcessEnv): WhatsappTransportName {
  const raw = (env.WHATSAPP_TRANSPORT ?? "").trim().toLowerCase();
  if (raw === "" || raw === "make") return "make";
  if (raw === "meta") return "meta";
  throw new Error(`WHATSAPP_TRANSPORT non valido: "${raw}" (ammessi: make, meta)`);
}

/** Configurazione Meta senza il token, che arriva da Secret Manager a runtime. */
export type MetaSettings = Omit<MetaConfig, "accessToken">;

function requiredEnv(env: NodeJS.ProcessEnv, key: string, pattern: RegExp, hint: string): string {
  const value = (env[key] ?? "").trim();
  if (!pattern.test(value)) {
    throw new Error(`${key} mancante o non valida con WHATSAPP_TRANSPORT=meta (atteso ${hint})`);
  }
  return value;
}

export function readMetaSettings(env: NodeJS.ProcessEnv): MetaSettings {
  const lang = (env.META_WA_TEMPLATE_LANG ?? "").trim() || "it";
  const booked = (env.META_WA_TEMPLATE_BOOKED ?? "").trim();
  return {
    graphVersion: requiredEnv(env, "META_GRAPH_VERSION", /^v\d+\.\d+$/, "es. v26.0"),
    phoneNumberId: requiredEnv(env, "META_WA_PHONE_NUMBER_ID", /^\d+$/, "l'id numerico del numero, non il telefono"),
    templates: {
      reminder: {
        name: requiredEnv(env, "META_WA_TEMPLATE_REMINDER", /^[a-z0-9_]+$/, "il nome del template approvato"),
        lang,
      },
      ...(booked ? { booked: { name: booked, lang } } : {}),
    },
  };
}

export function isWhatsappRecipientAllowed(e164: string, env: NodeJS.ProcessEnv): boolean {
  if (env.APP_ENV !== "staging" && env.FUNCTIONS_EMULATOR !== "true") return true;
  const allowed = (env.STAGING_WHATSAPP_ALLOWLIST ?? "")
    .split(",")
    .map((entry) => normalizePhoneE164(entry).e164)
    .filter((entry): entry is string => entry !== null);
  return allowed.includes(e164);
}
