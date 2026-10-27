// Body del Custom webhook Make. È un CONTRATTO con lo scenario: Make impara lo
// schema dal primo payload, quindi aggiungere o rinominare una chiave richiede
// un "Redetermine data structure" lato Make, altrimenti il campo non è
// selezionabile nei moduli a valle. Un solo evento (il promemoria del giorno
// prima), quindi nessun campo che distingua il tipo di messaggio.

import { formatGiorno, formatOrario } from "./format";

/**
 * Le chiavi coincidono con le variabili del template (`{{lezione}}`,
 * `{{giorno_lezione}}`, `{{orario_lezione}}`); `numero_di_telefono` è il
 * destinatario.
 */
export interface DemoLessonPayload {
  numero_di_telefono: string;
  lezione: string;
  giorno_lezione: string;
  orario_lezione: string;
}

/**
 * I parametri dei template WhatsApp non ammettono newline, tab né 4+ spazi
 * consecutivi (Meta rifiuta il messaggio): collasso ogni spazio bianco in uno.
 */
export function sanitizeTemplateParam(value: string | null | undefined): string {
  if (value === null || value === undefined) return "";
  return value.replace(/\s+/g, " ").trim();
}

export interface BuildPayloadArgs {
  phoneE164: string;
  lezione: string;
  startAtMillis: number;
  /** Override della data formattata: solo per la callable di prova. */
  giornoLezione?: string;
  /** Override dell'orario formattato: solo per la callable di prova. */
  orarioLezione?: string;
}

/**
 * Costruisce il body. I chiamanti scartano a monte chi non ha telefono o corso:
 * un campo vuoto qui è un bug da far emergere, non un caso da inviare.
 */
export function buildDemoLessonPayload(args: BuildPayloadArgs): DemoLessonPayload {
  const payload: DemoLessonPayload = {
    numero_di_telefono: args.phoneE164,
    lezione: sanitizeTemplateParam(args.lezione),
    giorno_lezione: sanitizeTemplateParam(args.giornoLezione) || formatGiorno(args.startAtMillis),
    orario_lezione: sanitizeTemplateParam(args.orarioLezione) || formatOrario(args.startAtMillis),
  };

  for (const [key, value] of Object.entries(payload)) {
    if (value === "") {
      throw new Error(
        `Campo "${key}" vuoto nel payload Make: i parametri del template WhatsApp non ammettono valori vuoti`
      );
    }
  }
  return payload;
}
