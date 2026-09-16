import {
  MigrationDecision,
  ReasonCode,
  SubscriptionMigrationTarget,
} from "./types";

type Data = Record<string, unknown>;

const MONTHS_BY_TYPE: Record<string, number> = {
  ABBONAMENTO_MENSILE: 1,
  ABBONAMENTO_TRIMESTRALE: 3,
  ABBONAMENTO_SEMESTRALE: 6,
  ABBONAMENTO_ANNUALE: 12,
};

const PLAN_VARIANT: Record<string, string> = {
  "2": "2x",
  "3": "3x",
  null: "unlim",
};

const TRIAL_DAYS = 30;
const PACKAGE_MONTHS = 3;
const PACKAGE_ENTRIES = 10;

export interface FutureBookingForMigration {
  courseId: string;
  startDateMillis: number;
  courseTypeTag: string | null;
}

interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  millisecond: number;
}

const formatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Europe/Rome",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});

function zonedParts(millis: number): ZonedParts {
  const values: Record<string, number> = {};
  for (const part of formatter.formatToParts(new Date(millis))) {
    if (part.type !== "literal") values[part.type] = Number(part.value);
  }
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour,
    minute: values.minute,
    second: values.second,
    millisecond: ((millis % 1000) + 1000) % 1000,
  };
}

function localSerial(parts: ZonedParts): number {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
    parts.millisecond
  );
}

/** Converte componenti locali Europe/Rome in istante, anche attraverso DST. */
function fromRomeParts(parts: ZonedParts): number {
  const wanted = localSerial(parts);
  let guess = wanted;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const delta = wanted - localSerial(zonedParts(guess));
    guess += delta;
    if (delta === 0) break;
  }
  return guess;
}

/** Sottrazione nominale con clamp di fine mese nel calendario Europe/Rome. */
export function subtractMonthsInRome(endMillis: number, months: number): number {
  const end = zonedParts(endMillis);
  const zeroBased = end.month - 1 - months;
  const targetYear = end.year + Math.floor(zeroBased / 12);
  const targetMonthIndex = ((zeroBased % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(targetYear, targetMonthIndex + 1, 0)).getUTCDate();
  return fromRomeParts({
    ...end,
    year: targetYear,
    month: targetMonthIndex + 1,
    day: Math.min(end.day, lastDay),
  });
}

/** Addizione nominale con clamp di fine mese nel calendario Europe/Rome. */
export function addMonthsInRome(startMillis: number, months: number): number {
  const start = zonedParts(startMillis);
  const zeroBased = start.month - 1 + months;
  const targetYear = start.year + Math.floor(zeroBased / 12);
  const targetMonthIndex = ((zeroBased % 12) + 12) % 12;
  const lastDay = new Date(
    Date.UTC(targetYear, targetMonthIndex + 1, 0)
  ).getUTCDate();
  return fromRomeParts({
    ...start,
    year: targetYear,
    month: targetMonthIndex + 1,
    day: Math.min(start.day, lastDay),
  });
}

export function timestampMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" &&
      "toMillis" in value && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}

export function deterministicSubscriptionId(
  documentId: string,
  family: "OPEN" | "PT" = "OPEN"
): string {
  return `legacy_${family.toLowerCase()}_${documentId}`;
}

function exactTags(tags: unknown, expected: string): boolean {
  return Array.isArray(tags) && tags.length === 1 && tags[0] === expected;
}

function entryBalance(data: Data, maximum: number): number | null {
  const value = data.entrateDisponibili;
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) return null;
  return value <= maximum ? value : Number.POSITIVE_INFINITY;
}

function uncoveredFutureBooking(
  bookings: FutureBookingForMigration[],
  target: SubscriptionMigrationTarget
): FutureBookingForMigration | undefined {
  return bookings.find((booking) =>
    booking.startDateMillis < target.startDateMillis ||
    booking.startDateMillis > target.endDateMillis ||
    booking.courseTypeTag === null ||
    !target.courseTypeTags.includes(booking.courseTypeTag)
  );
}

export function transformUser(
  documentId: string,
  data: Data,
  evaluatedAtMillis: number,
  futureBookings: FutureBookingForMigration[] = []
): MigrationDecision<SubscriptionMigrationTarget> {
  const tags = data.tipologiaCorsoTags;
  if (Array.isArray(tags) && tags.includes("Hey Mamma")) {
    return ignored("HEY_MAMMA", "utente storico Hey Mamma");
  }
  if (data.role !== "User") {
    return ignored("ROLE_NOT_USER", `role=${String(data.role)}`);
  }

  const legacyType = data.tipologiaIscrizione;
  const endDateMillis = timestampMillis(data.fineIscrizione);
  if (endDateMillis === null) {
    return ignored("MISSING_END_DATE", "fineIscrizione assente o invalida");
  }

  let target: SubscriptionMigrationTarget;
  if (legacyType === "ABBONAMENTO_PROVA") {
    if (!exactTags(tags, "Open")) {
      return ignored(
        "INVALID_TAG_SHAPE",
        `la prova richiede il solo tag Open: ${JSON.stringify(tags)}`
      );
    }
    const remaining = entryBalance(data, 1);
    if (remaining === null) {
      return ignored("INVALID_ENTRY_BALANCE", "entrateDisponibili negativo o invalido");
    }
    if (!Number.isFinite(remaining)) {
      return ignored("ENTRY_BALANCE_EXCEEDS_PLAN", "la prova ammette al massimo 1 ingresso");
    }
    const startDateMillis = endDateMillis - TRIAL_DAYS * 86400000;
    if (startDateMillis > evaluatedAtMillis) {
      return ignored("FUTURE_START", "la data iniziale nominale e successiva al dry-run");
    }
    target = {
      id: deterministicSubscriptionId(documentId),
      userId: documentId,
      createdBy: "legacy-migration",
      planKey: "open_trial_1i_30d",
      family: "OPEN",
      billingMode: "ENTRIES",
      courseTypeTags: ["Open"],
      weeklyFrequency: null,
      remainingEntries: remaining,
      startDateMillis,
      endDateMillis,
      createdAtMillis: evaluatedAtMillis,
    };
  } else if (legacyType === "PACCHETTO_ENTRATE") {
    const family = exactTags(tags, "Open")
      ? "OPEN"
      : exactTags(tags, "Personal Trainer") ? "PT" : null;
    if (family === null) {
      return ignored(
        "INVALID_TAG_SHAPE",
        `il pacchetto richiede un solo tag Open o Personal Trainer: ${JSON.stringify(tags)}`
      );
    }
    const remaining = entryBalance(data, PACKAGE_ENTRIES);
    if (remaining === null) {
      return ignored("INVALID_ENTRY_BALANCE", "entrateDisponibili negativo o invalido");
    }
    if (!Number.isFinite(remaining)) {
      return ignored(
        "ENTRY_BALANCE_EXCEEDS_PLAN",
        `entrateDisponibili supera il massimo ${PACKAGE_ENTRIES}`
      );
    }
    const startDateMillis = subtractMonthsInRome(endDateMillis, PACKAGE_MONTHS);
    if (startDateMillis > evaluatedAtMillis) {
      return ignored("FUTURE_START", "la data iniziale nominale e successiva al dry-run");
    }
    const prefix = family === "OPEN" ? "open" : "pt";
    const tag = family === "OPEN" ? "Open" : "Personal Trainer";
    target = {
      id: deterministicSubscriptionId(documentId, family),
      userId: documentId,
      createdBy: "legacy-migration",
      planKey: `${prefix}_10i_3m`,
      family,
      billingMode: "ENTRIES",
      courseTypeTags: [tag],
      weeklyFrequency: null,
      remainingEntries: remaining,
      startDateMillis,
      endDateMillis,
      createdAtMillis: evaluatedAtMillis,
    };
  } else {
  if (typeof legacyType !== "string" || MONTHS_BY_TYPE[legacyType] === undefined) {
    return ignored("INVALID_LEGACY_TYPE", `tipologia=${String(legacyType)}`);
  }
  if (!Array.isArray(tags) || tags.length !== 1 || tags[0] !== "Open") {
    return ignored(
      "INVALID_TAG_SHAPE",
      `tipologiaCorsoTags=${JSON.stringify(tags)}`
    );
  }

  const weekly = data.entrateSettimanali;
  if (weekly !== null && weekly !== 2 && weekly !== 3) {
    return ignored(
      "INVALID_WEEKLY_FREQUENCY",
      `entrateSettimanali=${String(weekly)}`
    );
  }
  const months = MONTHS_BY_TYPE[legacyType];
  const startDateMillis = subtractMonthsInRome(endDateMillis, months);
  if (startDateMillis > evaluatedAtMillis) {
    return ignored(
      "FUTURE_START",
      "la data iniziale nominale e successiva al dry-run"
    );
  }

  const id = deterministicSubscriptionId(documentId);
  const variant = PLAN_VARIANT[String(weekly)];
  target = {
    id,
    userId: documentId,
    createdBy: "legacy-migration",
    planKey: `open_${variant}_${months}m`,
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency: weekly as 2 | 3 | null,
    remainingEntries: null,
    startDateMillis,
    endDateMillis,
    createdAtMillis: evaluatedAtMillis,
  };
  }

  const uncovered = uncoveredFutureBooking(futureBookings, target);
  if (uncovered) {
    return ignored(
      "FUTURE_BOOKING_NOT_COVERED",
      `prenotazione futura ${uncovered.courseId} non coperta dal target`
    );
  }
  return {
    conversionStatus: "CONVERTIBLE",
    reasonCode: "OK",
    reasonDetail: "corrispondenza legacy esatta",
    target,
  };
}

function ignored(
  reasonCode: Exclude<ReasonCode, "OK" | "ALREADY_APPLIED" | "EXISTING_SUBSCRIPTION_CONFLICT">,
  reasonDetail: string
): MigrationDecision<SubscriptionMigrationTarget> {
  return {
    conversionStatus: "IGNORED",
    reasonCode,
    reasonDetail,
    target: null,
  };
}
