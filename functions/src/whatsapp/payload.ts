// Body del Custom webhook Make. È un CONTRATTO con lo scenario: Make impara lo
// schema dal primo payload, quindi aggiungere o rinominare una chiave richiede
// un "Redetermine data structure" lato Make, altrimenti il campo non è
// selezionabile nei moduli a valle. La chiave di autenticazione NON sta qui:
// viaggia nell'header `Demo-Reminder` (makeClient.ts).

import { formatGiorno, formatOrario } from "./format";

export type DemoWebhookKind = "booked" | "reminder";

/** Valore del campo `tipo`, su cui il Router di Make sceglie il template. */
export const TIPO_BY_KIND: Record<DemoWebhookKind, string> = {
  booked: "conferma",
  reminder: "promemoria",
};

export interface DemoLessonPayload {
  tipo: string;
  nome: string;
  numero_di_telefono: string;
  corso: string;
  giorno: string;
  orario: string;
}

/**
 * I parametri dei template WhatsApp non ammettono newline, tab né 4+ spazi
 * consecutivi (Meta rifiuta il messaggio): collasso ogni spazio bianco in uno.
 */
export function sanitizeTemplateParam(value: string | null | undefined): string {
  if (value === null || value === undefined) return "";
  return value.replace(/\s+/g, " ").trim();
}

/** `"Mario Rossi"` da nome e cognome, tollerando l'assenza del cognome. */
export function buildNome(
  name: string | null | undefined,
  lastName: string | null | undefined
): string {
  return sanitizeTemplateParam(`${name ?? ""} ${lastName ?? ""}`);
}

export interface BuildPayloadArgs {
  kind: DemoWebhookKind;
  nome: string;
  phoneE164: string;
  corso: string;
  startAtMillis: number;
  /** Override della data formattata: solo per la callable di prova. */
  giorno?: string;
  /** Override dell'orario formattato: solo per la callable di prova. */
  orario?: string;
}

/**
 * Costruisce il body. I chiamanti scartano a monte chi non ha nome o telefono:
 * un campo vuoto qui è un bug da far emergere, non un caso da inviare.
 */
export function buildDemoLessonPayload(args: BuildPayloadArgs): DemoLessonPayload {
  const payload: DemoLessonPayload = {
    tipo: TIPO_BY_KIND[args.kind],
    nome: sanitizeTemplateParam(args.nome),
    numero_di_telefono: args.phoneE164,
    corso: sanitizeTemplateParam(args.corso),
    giorno: sanitizeTemplateParam(args.giorno) || formatGiorno(args.startAtMillis),
    orario: sanitizeTemplateParam(args.orario) || formatOrario(args.startAtMillis),
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
