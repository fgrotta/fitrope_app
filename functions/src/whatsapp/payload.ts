// Parametri del template WhatsApp e body del Custom webhook Make.
//
// I parametri (`buildTemplateParams`) sono gli stessi per entrambi i trasporti.
// Il body Make (`toMakeBody`) è un CONTRATTO con lo scenario: Make impara lo
// schema dal primo payload, quindi aggiungere o rinominare una chiave richiede
// un "Redetermine data structure" lato Make, altrimenti il campo non è
// selezionabile nei moduli a valle. La chiave di autenticazione NON sta qui:
// viaggia nell'header `Demo-Reminder` (makeClient.ts).

import { formatGiorno, formatOrario } from "./format";
import type { TemplateParams } from "./transport";

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
  nome: string;
  corso: string;
  startAtMillis: number;
  /** Override della data formattata: solo per la callable di prova. */
  giorno?: string;
  /** Override dell'orario formattato: solo per la callable di prova. */
  orario?: string;
}

function assertNoEmptyField(fields: Record<string, string>): void {
  for (const [key, value] of Object.entries(fields)) {
    if (value === "") {
      throw new Error(
        `Campo "${key}" vuoto nel messaggio WhatsApp: i parametri del template non ammettono valori vuoti`
      );
    }
  }
}

/**
 * Parametri del template, comuni a Make e Meta. I chiamanti scartano a monte
 * chi non ha nome o telefono: un campo vuoto qui è un bug da far emergere, non
 * un caso da inviare.
 */
export function buildTemplateParams(args: BuildPayloadArgs): TemplateParams {
  const params: TemplateParams = {
    nome: sanitizeTemplateParam(args.nome),
    corso: sanitizeTemplateParam(args.corso),
    giorno: sanitizeTemplateParam(args.giorno) || formatGiorno(args.startAtMillis),
    orario: sanitizeTemplateParam(args.orario) || formatOrario(args.startAtMillis),
  };
  assertNoEmptyField({ ...params });
  return params;
}

/** Body del Custom webhook Make: il contratto con lo scenario, invariato. */
export function toMakeBody(
  kind: DemoWebhookKind,
  phoneE164: string,
  params: TemplateParams
): DemoLessonPayload {
  const payload: DemoLessonPayload = {
    tipo: TIPO_BY_KIND[kind],
    nome: params.nome,
    numero_di_telefono: phoneE164,
    corso: params.corso,
    giorno: params.giorno,
    orario: params.orario,
  };
  assertNoEmptyField({ ...payload });
  return payload;
}

/** Body Make completo a partire dai dati della lezione. */
export function buildDemoLessonPayload(
  args: BuildPayloadArgs & { kind: DemoWebhookKind; phoneE164: string }
): DemoLessonPayload {
  return toMakeBody(args.kind, args.phoneE164, buildTemplateParams(args));
}
