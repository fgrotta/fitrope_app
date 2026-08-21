const ROME_TZ = "Europe/Rome";

export interface RomeParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  isoWeekday: number;
}

export function romeParts(millis: number): RomeParts {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: ROME_TZ,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  const map: Record<string, string> = {};
  for (const part of dtf.formatToParts(new Date(millis))) map[part.type] = part.value;
  const year = Number(map.year);
  const month = Number(map.month);
  const day = Number(map.day);
  const hour = Number(map.hour) === 24 ? 0 : Number(map.hour);
  const dow = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return {
    year,
    month,
    day,
    hour,
    minute: Number(map.minute),
    isoWeekday: ((dow + 6) % 7) + 1,
  };
}

function romeOffsetMillis(date: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: ROME_TZ,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const map: Record<string, string> = {};
  for (const part of dtf.formatToParts(date)) map[part.type] = part.value;
  const hour = Number(map.hour) === 24 ? 0 : Number(map.hour);
  const asUtc = Date.UTC(
    Number(map.year),
    Number(map.month) - 1,
    Number(map.day),
    hour,
    Number(map.minute),
    Number(map.second)
  );
  return asUtc - date.getTime();
}

export function romeWallClockToUtcMillis(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number
): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const offset = romeOffsetMillis(new Date(guess));
  return guess - offset;
}

/** Settimana civile Europe/Rome: lunedì 00:00 fino al lunedì seguente escluso. */
export function romeWeekBoundsMillis(millis: number): { start: number; end: number } {
  const local = romeParts(millis);
  const monday = new Date(
    Date.UTC(local.year, local.month - 1, local.day - (local.isoWeekday - 1))
  );
  const nextMonday = new Date(
    Date.UTC(monday.getUTCFullYear(), monday.getUTCMonth(), monday.getUTCDate() + 7)
  );
  const start = romeWallClockToUtcMillis(
    monday.getUTCFullYear(),
    monday.getUTCMonth() + 1,
    monday.getUTCDate(),
    0,
    0
  );
  const next = romeWallClockToUtcMillis(
    nextMonday.getUTCFullYear(),
    nextMonday.getUTCMonth() + 1,
    nextMonday.getUTCDate(),
    0,
    0
  );
  return { start, end: next - 1 };
}
