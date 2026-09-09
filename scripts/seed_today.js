#!/usr/bin/env node
/**
 * Aggiunge una giornata di corsi su OGGI nell'emulatore Firestore.
 *
 * Serve perche' `functions/scripts/seedEmulator.js` colloca i corsi nella
 * settimana SUCCESSIVA: il calendario si apre sulla data odierna e sembra
 * vuoto, come se il seed fosse fallito. Qui si semina la giornata corrente con
 * stati diversi (posti liberi, quasi pieno, pieno) per avere qualcosa da
 * guardare senza navigare.
 *
 * Scrive via REST col token `owner`, quindi bypassa le rules e non serve ADC.
 */
const PROJECT = process.env.EMULATOR_PROJECT || 'fit-rope-app-1f575';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
const BASE =
  `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

const ITALIAN_TIME_ZONE = 'Europe/Rome';

// Ricava le componenti di un istante nel fuso italiano. Usare `getUTCDate()` o
// l'offset del Mac non basta: subito dopo mezzanotte in Italia la data UTC può
// essere ancora quella del giorno precedente.
const italianParts = (instant) => Object.fromEntries(
  new Intl.DateTimeFormat('en-GB', {
    timeZone: ITALIAN_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  })
    .formatToParts(instant)
    .filter(({ type }) => type !== 'literal')
    .map(({ type, value }) => [type, Number(value)]),
);

// Offset Europe/Rome valido per QUELL'istante. Viene calcolato con Intl, quindi
// vale +1 in inverno e +2 in estate senza tabelle DST mantenute a mano.
const italianOffsetMs = (instant) => {
  const p = italianParts(instant);
  const representedAsUtc = Date.UTC(
    p.year,
    p.month - 1,
    p.day,
    p.hour,
    p.minute,
    p.second,
  );
  return representedAsUtc - instant.getTime();
};

const italianWallTimeToDate = ({ year, month, day, hour, minute = 0 }) => {
  const wallTimeAsUtc = Date.UTC(year, month - 1, day, hour, minute, 0);
  let result = new Date(wallTimeAsUtc);

  // Due passaggi coprono anche il caso in cui il primo tentativo cada dal lato
  // opposto di una transizione DST rispetto all'orario locale richiesto.
  for (let i = 0; i < 2; i += 1) {
    result = new Date(wallTimeAsUtc - italianOffsetMs(result));
  }
  return result;
};

const isoForItalianToday = (hour, now = new Date()) => {
  const { year, month, day } = italianParts(now);
  return italianWallTimeToDate({ year, month, day, hour })
    .toISOString()
    .replace(/\.\d{3}Z$/, 'Z');
};

const CORSI = [
  ['oggi-open-am',   'Open mattina',      'Open',             'Sala 1',  7, 12,  4],
  ['oggi-hyrox',     'Hyrox base',        'Hyrox',            'Sala 2',  9,  8,  6],
  ['oggi-heymamma',  'Hey Mamma',         'Hey Mamma',        'Sala 1', 10, 12,  3],
  ['oggi-pt',        'Personal Training', 'Personal Trainer', 'Sala 1', 14,  1,  0],
  ['oggi-open-pm',   'Open pomeriggio',   'Open',             'Sala 1', 17, 12, 11],
  ['oggi-hyrox-pm',  'Hyrox avanzato',    'Hyrox',            'Sala 2', 19,  8,  8],
];

// Un solo istante di riferimento per tutto il seed: anche se l'esecuzione
// attraversasse la mezzanotte, tutti i corsi restano nella stessa giornata.
const seedNow = new Date();
const iso = (hour) => isoForItalianToday(hour, seedNow);

const doc = ([id, name, tag, sala, hour, capacity, subscribed]) => ({
  fields: {
    id: { stringValue: id },
    uid: { stringValue: id },
    name: { stringValue: name },
    startDate: { timestampValue: iso(hour) },
    endDate: { timestampValue: iso(hour + 1) },
    capacity: { integerValue: String(capacity) },
    subscribed: { integerValue: String(subscribed) },
    trainerId: { stringValue: 'trainer-test' },
    tags: { arrayValue: { values: [{ stringValue: tag }] } },
    waitlist: { arrayValue: {} },
    reminderEnabled: { booleanValue: true },
    waitlistEnabled: { booleanValue: true },
    sala: { stringValue: sala },
  },
});

const seed = async () => {
  for (const corso of CORSI) {
    const res = await fetch(`${BASE}/courses/${corso[0]}`, {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer owner',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(doc(corso)),
    });
    if (!res.ok) {
      console.error(`  ✗ ${corso[1]}: ${res.status} ${await res.text()}`);
      process.exitCode = 1;
      continue;
    }
    console.log(`  + ${corso[1]} (${String(corso[4]).padStart(2, '0')}:00)`);
  }
};

if (require.main === module) {
  seed().catch((error) => {
    console.error(`Seed fallito: ${error}`);
    process.exitCode = 1;
  });
}

module.exports = {
  isoForItalianToday,
  italianParts,
  italianWallTimeToDate,
};
