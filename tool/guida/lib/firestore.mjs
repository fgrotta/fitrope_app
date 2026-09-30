// Scritture dirette sull'emulatore Firestore, per preparare lo stato che uno
// scenario vuole fotografare (un certificato scaduto, un utente legacy
// convertibile…) senza passare dalla UI. Il token `owner` bypassa le rules:
// funziona SOLO sull'emulatore, in produzione verrebbe rifiutato.

const PROJECT = 'fit-rope-app-1f575';

export class EmulatorFirestore {
  constructor(port) {
    this.base =
      `http://localhost:${port}/v1/projects/${PROJECT}/databases/(default)/documents`;
  }

  /** Aggiorna (o crea) solo i campi indicati di `collection/doc`. */
  async patch(docPath, fields) {
    const mask = Object.keys(fields)
      .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
      .join('&');
    const res = await fetch(`${this.base}/${docPath}?${mask}`, {
      method: 'PATCH',
      headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: toFields(fields) }),
    });
    if (!res.ok) throw new Error(`PATCH ${docPath} → ${res.status} ${await res.text()}`);
  }

  /** Documenti di [collection] con `field == value`: `[{ id, data }]`. */
  async where(collection, field, value) {
    const res = await fetch(`${this.base}:runQuery`, {
      method: 'POST',
      headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: collection }],
          where: {
            fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: toValue(value) },
          },
        },
      }),
    });
    if (!res.ok) throw new Error(`runQuery ${collection} → ${res.status}`);
    return (await res.json())
      .filter((row) => row.document)
      .map((row) => ({
        id: row.document.name.split('/').pop(),
        data: fromFields(row.document.fields ?? {}),
      }));
  }

  async get(docPath) {
    const res = await fetch(`${this.base}/${docPath}`, {
      headers: { Authorization: 'Bearer owner' },
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`GET ${docPath} → ${res.status}`);
    return fromFields((await res.json()).fields ?? {});
  }
}

/** Giorni da oggi, all'ora indicata (fuso della macchina). */
export function daysFromNow(days, hour = 12) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  d.setHours(hour, 0, 0, 0);
  return d;
}

/** Lunedì della settimana prossima, dove il seed mette i suoi corsi. */
export function nextMonday(hour = 12) {
  const d = new Date();
  const weekday = (d.getDay() + 6) % 7; // lunedì = 0
  d.setDate(d.getDate() + 7 - weekday);
  d.setHours(hour, 0, 0, 0);
  return d;
}

/**
 * [date] + [months] mesi di calendario, alla fine del mese se il giorno non
 * esiste (31/01 + 1 → 28/02): la stessa regola dei piani dell'app.
 */
export function addMonths(date, months) {
  const d = new Date(date);
  const day = d.getDate();
  d.setDate(1);
  d.setMonth(d.getMonth() + months);
  const last = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  d.setDate(Math.min(day, last));
  return d;
}

function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  switch (typeof v) {
    case 'boolean':
      return { booleanValue: v };
    case 'number':
      return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
    case 'string':
      return { stringValue: v };
    case 'object':
      return { mapValue: { fields: toFields(v) } };
    default:
      throw new Error(`Tipo non supportato: ${typeof v}`);
  }
}

function toFields(obj) {
  return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toValue(v)]));
}

function fromValue(v) {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(fromValue);
  if ('mapValue' in v) return fromFields(v.mapValue.fields ?? {});
  return undefined;
}

function fromFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, fromValue(v)]));
}
