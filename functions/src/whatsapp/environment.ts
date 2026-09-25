// Cosa esiste e a chi si può scrivere, in base all'ambiente.
//
// WHATSAPP_DEMO_MODE (in `.env.<projectId>`, letta dalla CLI prima della
// discovery degli export, come i gate dei certificati in index.ts):
//   off  (default, e per qualunque valore sconosciuto) → niente WhatsApp;
//   test → solo la callable di prova (Admin), per verificare lo scenario Make;
//   live → + conferma all'iscrizione + cron dei promemoria.
//
// Su staging i dati possono essere un clone della produzione, con numeri reali:
// lì un numero passa solo se è in STAGING_WHATSAPP_ALLOWLIST (lista separata da
// virgole, anche senza prefisso: viene normalizzata). Stessa regola
// sull'emulatore: parte con `--project fit-rope-app-1f575`, quindi eredita la
// modalità della produzione, legge i secret Make da Secret Manager se mancano
// in `.secret.local` e può contenere un export dei dati reali.

import { normalizePhoneE164 } from "./phone";

export type WhatsappDemoMode = "off" | "test" | "live";

export function whatsappDemoMode(env: NodeJS.ProcessEnv): WhatsappDemoMode {
  const raw = (env.WHATSAPP_DEMO_MODE ?? "").trim().toLowerCase();
  return raw === "test" || raw === "live" ? raw : "off";
}

export function isWhatsappRecipientAllowed(e164: string, env: NodeJS.ProcessEnv): boolean {
  if (env.APP_ENV !== "staging" && env.FUNCTIONS_EMULATOR !== "true") return true;
  const allowed = (env.STAGING_WHATSAPP_ALLOWLIST ?? "")
    .split(",")
    .map((entry) => normalizePhoneE164(entry).e164)
    .filter((entry): entry is string => entry !== null);
  return allowed.includes(e164);
}
