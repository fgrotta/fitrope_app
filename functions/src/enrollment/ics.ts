// Generazione del file iCalendar (RFC 5545) per una lezione, servito dalla
// function HTTP `courseIcs`. E' la strada "aggiungi al calendario" per i client
// che non sono Google Calendar (Apple Calendar, Outlook, ...) ed e' l'unica che
// permette di imporre un promemoria: il deeplink Google non ha parametri per gli
// alert, quindi il VALARM a -4h vive solo qui.

import {
  eventDescription,
  eventLocation,
  formatUtcStamp,
} from "./calendarLinks";

const PRODID = "-//Fit House Monza//FitRope//IT";
const UID_DOMAIN = "fithousemonza.it";
const ALARM_TRIGGER = "-PT4H";
const MAX_OCTETS = 75;

/**
 * Escaping dei valori TEXT di RFC 5545 §3.3.11. I nomi dei corsi contengono
 * virgole ("Hey Mamma, sala 2"): senza escaping l'evento si corrompe, perche' la
 * virgola separa piu' valori nello stesso campo.
 */
export function escapeIcsText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r\n|\r|\n/g, "\\n");
}

/**
 * Content line folding (RFC 5545 §3.1): righe di massimo 75 ottetti, le
 * successive iniziano con uno spazio. Il conteggio e' in ottetti UTF-8, non in
 * caratteri: i nomi accentati e le emoji occupano piu' di un byte.
 */
export function foldLine(line: string): string {
  const bytes = Buffer.from(line, "utf8");
  if (bytes.length <= MAX_OCTETS) return line;

  const chunks: string[] = [];
  let start = 0;
  let limit = MAX_OCTETS;
  while (start < bytes.length) {
    let end = Math.min(start + limit, bytes.length);
    // Non spezzare in mezzo a una sequenza multi-byte UTF-8: i byte di
    // continuazione hanno i due bit alti a `10`.
    while (end > start && end < bytes.length && (bytes[end] & 0xc0) === 0x80) {
      end -= 1;
    }
    chunks.push(bytes.subarray(start, end).toString("utf8"));
    start = end;
    limit = MAX_OCTETS - 1; // lo spazio iniziale delle righe piegate conta
  }
  return chunks.join("\r\n ");
}

export interface CourseIcsArgs {
  courseId: string;
  courseName: string;
  startMillis: number;
  endMillis: number;
  sala?: string | null;
  nowMillis: number;
}

/** Documento VCALENDAR con un singolo VEVENT e il promemoria a -4h. */
export function buildCourseIcs(args: CourseIcsArgs): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${PRODID}`,
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:course-${args.courseId}@${UID_DOMAIN}`,
    `DTSTAMP:${formatUtcStamp(args.nowMillis)}`,
    `DTSTART:${formatUtcStamp(args.startMillis)}`,
    `DTEND:${formatUtcStamp(args.endMillis)}`,
    `SUMMARY:${escapeIcsText(args.courseName)}`,
    `LOCATION:${escapeIcsText(eventLocation(args.sala))}`,
    `DESCRIPTION:${escapeIcsText(eventDescription())}`,
    "STATUS:CONFIRMED",
    "SEQUENCE:0",
    "BEGIN:VALARM",
    "ACTION:DISPLAY",
    `TRIGGER:${ALARM_TRIGGER}`,
    `DESCRIPTION:${escapeIcsText(args.courseName)}`,
    "END:VALARM",
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  // CRLF obbligatorio da RFC 5545, e riga vuota finale: alcuni parser
  // (Outlook desktop) scartano il file se manca il terminatore.
  return `${lines.map(foldLine).join("\r\n")}\r\n`;
}
