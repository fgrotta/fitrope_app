// Date e orari del body WhatsApp nel fuso Europe/Rome.
//
// Riusa gli helper di enrollment/notify.ts invece di aggiungere una quarta
// implementazione dell'offset di Roma. La conversione wall-clock → UTC di
// notify.ts è a passo singolo, ma a mezzanotte è esatta: in Europa l'ora
// cambia alle 01:00 UTC, quindi mai tra la mezzanotte locale e la mezzanotte UTC.

import { romeParts, romeWallClockToUtcMillis } from "../enrollment/notify";

/** Mesi in italiano con l'iniziale maiuscola: è il formato atteso dal template. */
export const MONTH_NAMES_IT = [
  "Gennaio",
  "Febbraio",
  "Marzo",
  "Aprile",
  "Maggio",
  "Giugno",
  "Luglio",
  "Agosto",
  "Settembre",
  "Ottobre",
  "Novembre",
  "Dicembre",
];

/**
 * `"28 Ottobre"` — campo `giorno_lezione` del body. Senza anno: il promemoria
 * parla sempre della lezione di domani.
 */
export function formatGiorno(millis: number): string {
  const p = romeParts(millis);
  return `${p.day} ${MONTH_NAMES_IT[p.month - 1]}`;
}

/** `"19:00"` — campo `orario_lezione` del body (solo l'ora di inizio). */
export function formatOrario(millis: number): string {
  const p = romeParts(millis);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

export interface RomeDayRange {
  startMs: number;
  endMs: number;
}

/** Intervallo UTC `[00:00, 23:59:59.999]` ora di Roma del giorno dopo `nowMillis`. */
export function tomorrowRomeRange(nowMillis: number): RomeDayRange {
  const p = romeParts(nowMillis);
  // Date.UTC normalizza day+1 / day+2 oltre la fine del mese.
  return {
    startMs: romeWallClockToUtcMillis(p.year, p.month, p.day + 1, 0, 0),
    endMs: romeWallClockToUtcMillis(p.year, p.month, p.day + 2, 0, 0) - 1,
  };
}
