// ──────────────────────────────────────────────
//  Utility di data/ora in Europe/Rome (DST-aware)
//
//  Estratto da certificateEmails.ts per essere condiviso con makeWebhook.ts.
//  L'unico uso di Intl è dentro `romeOffsetMinutes`, con locale "en-US" (quindi
//  locale-independent): tutte le stringhe utente sono derivate da `romeWallClock`,
//  così l'output non dipende dalla build ICU del runtime.
// ──────────────────────────────────────────────

export interface RomeDayWindow {
  startMs: number;
  endMs: number;
}

export interface RomeWallClock {
  /** Anno (es. 2026). */
  year: number;
  /** Mese 1-12. */
  month: number;
  /** Giorno del mese 1-31. */
  day: number;
  /** Ora 0-23. */
  hour: number;
  /** Minuto 0-59. */
  minute: number;
}

/** Nomi dei mesi in italiano, minuscoli: è il formato atteso dal webhook Make. */
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

/** Offset (in minuti) di Europe/Rome rispetto a UTC nell'istante `atUtc`. */
export function romeOffsetMinutes(atUtc: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  const parts: Record<string, string> = {};
  for (const p of dtf.formatToParts(atUtc)) parts[p.type] = p.value;
  const hour = parts.hour === "24" ? "0" : parts.hour;
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(hour),
    Number(parts.minute),
    Number(parts.second)
  );
  return (asUtc - atUtc.getTime()) / 60000;
}

/**
 * Restituisce la finestra UTC `[00:00, 23:59:59.999]` (ora di Roma) del giorno
 * `now + dayOffset` giorni civili. I certificati sono salvati a 23:59 ora di
 * Roma, quindi questa finestra li seleziona correttamente.
 */
export function romeDayWindow(now: Date, dayOffset: number): RomeDayWindow {
  const offNow = romeOffsetMinutes(now);
  // Sposto `now` di modo che i campi UTC corrispondano all'orologio di Roma.
  const romeNow = new Date(now.getTime() + offNow * 60000);
  const y = romeNow.getUTCFullYear();
  const mo = romeNow.getUTCMonth();
  const d = romeNow.getUTCDate() + dayOffset;

  const wallStart = Date.UTC(y, mo, d, 0, 0, 0, 0);
  const wallEnd = Date.UTC(y, mo, d, 23, 59, 59, 999);

  // Ricavo l'offset effettivo del giorno target (CET/CEST possono differire da oggi).
  const approx = new Date(wallStart - offNow * 60000);
  const offTarget = romeOffsetMinutes(approx);

  return {
    startMs: wallStart - offTarget * 60000,
    endMs: wallEnd - offTarget * 60000,
  };
}

/** Campi dell'orologio da parete di Roma per l'istante `atUtc`. */
export function romeWallClock(atUtc: Date): RomeWallClock {
  const shifted = new Date(atUtc.getTime() + romeOffsetMinutes(atUtc) * 60000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
  };
}

/** `"15 ottobre 2026"` — formato del campo `giorno` atteso dal webhook Make. */
export function formatGiorno(atUtc: Date): string {
  const { year, month, day } = romeWallClock(atUtc);
  return `${day} ${MONTH_NAMES_IT[month - 1]} ${year}`;
}

/** `"18:00"` — formato del campo `orario` atteso dal webhook Make. */
export function formatOrario(atUtc: Date): string {
  const { hour, minute } = romeWallClock(atUtc);
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

/**
 * Finestra UTC allargata di `padMinutes` su entrambi i lati rispetto al giorno
 * civile di Roma `now + dayOffset`.
 *
 * Serve perché `romeDayWindow` calcola un solo offset (quello della mezzanotte
 * del giorno target) e lo applica a entrambi gli estremi. Nei due giorni di
 * cambio ora questo produce una finestra sfasata di un'ora:
 *   - spring-forward (es. 29/03/2026): sfora di 1h nel giorno successivo;
 *   - fall-back (es. 25/10/2026): si chiude 1h prima, quindi un documento tra
 *     le 23:00 e le 23:59 ora di Roma resterebbe fuori dalla query.
 *
 * Per i certificati (salvati a 23:59) l'effetto è innocuo e il comportamento di
 * `romeDayWindow` resta invariato; chi ha bisogno di precisione al minuto usa
 * questa finestra per la query e poi filtra in memoria con `isSameRomeDay`.
 */
export function romeDayWindowPadded(
  now: Date,
  dayOffset: number,
  padMinutes = 120
): RomeDayWindow {
  const w = romeDayWindow(now, dayOffset);
  return {
    startMs: w.startMs - padMinutes * 60000,
    endMs: w.endMs + padMinutes * 60000,
  };
}

/** `true` se i due istanti cadono nello stesso giorno civile di Roma. */
export function isSameRomeDay(a: Date, b: Date): boolean {
  const wa = romeWallClock(a);
  const wb = romeWallClock(b);
  return wa.year === wb.year && wa.month === wb.month && wa.day === wb.day;
}
