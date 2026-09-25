// Date e orari del body WhatsApp nel fuso Europe/Rome.
//
// Riusa gli helper di enrollment/notify.ts invece di aggiungere una quarta
// implementazione dell'offset di Roma. La conversione wall-clock → UTC di
// notify.ts è a passo singolo, ma a mezzanotte è esatta: in Europa l'ora
// cambia alle 01:00 UTC, quindi mai tra la mezzanotte locale e la mezzanotte UTC.

import { romeParts, romeWallClockToUtcMillis } from "../enrollment/notify";

/** Mesi in italiano, minuscoli: è il formato atteso dallo scenario Make. */
export const MONTH_NAMES_IT = [
  "gennaio",
  "febbraio",
  "marzo",
  "aprile",
  "maggio",
  "giugno",
  "luglio",
  "agosto",
  "settembre",
  "ottobre",
  "novembre",
  "dicembre",
];

/** `"15 ottobre 2026"` — campo `giorno` del body. */
export function formatGiorno(millis: number): string {
  const p = romeParts(millis);
  return `${p.day} ${MONTH_NAMES_IT[p.month - 1]} ${p.year}`;
}

/** `"18:00"` — campo `orario` del body (solo l'ora di inizio). */
export function formatOrario(millis: number): string {
  const p = romeParts(millis);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

/** `true` se i due istanti cadono nello stesso giorno civile di Roma. */
export function isSameRomeDay(aMillis: number, bMillis: number): boolean {
  const a = romeParts(aMillis);
  const b = romeParts(bMillis);
  return a.year === b.year && a.month === b.month && a.day === b.day;
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
