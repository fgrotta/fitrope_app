// Costruzione dei link "aggiungi al calendario" per le email della lezione di prova.
//
// Due strade, perché nessuna copre tutti i client:
//  - deeplink Google Calendar (`render?action=TEMPLATE`): un click, zero download,
//    ma niente promemoria personalizzato (Google applica i default dell'utente);
//  - file `.ics` servito dalla function HTTP `courseIcs`: copre Apple Calendar,
//    Outlook e tutto il resto, e porta il VALARM a -4h.
//
// OneSignal non supporta allegati email (l'unico campo media dell'API Create
// Message e' `mms_media_urls`, per SMS): l'`.ics` DEVE essere un link, non un
// allegato.

const ICS_FUNCTION_NAME = "courseIcs";
const ICS_REGION = "europe-west8";
const ICS_EMULATOR_PORT = 5001; // firebase.json > emulators.functions.port

// Fallback allineato allo stile di ONESIGNAL_APP_ID in handler.ts: se il runtime
// non espone il project id, si assume la produzione.
const FALLBACK_PROJECT_ID = "fit-rope-app-1f575";

// Finisce nel campo LOCATION dell'evento calendario (e nel parametro `location`
// del deeplink Google): nome del locale + indirizzo, cosi' Google Maps lo
// risolve e il calendario mostra comunque un'etichetta leggibile.
// Le virgole sono volute: `escapeIcsText` le protegge nell'.ics.
export const GYM_ADDRESS =
  "Fit House Monza, Via Giuseppe Ferrari, 6, 20900 Monza";

const EVENT_DESCRIPTION =
  "La tua lezione di prova alla Fit House. " +
  "Ricordati abbigliamento comodo e una bottiglietta d'acqua.";

/** `YYYYMMDDTHHMMSSZ` (formato "basic" UTC di RFC 5545 / Google Calendar). */
export function formatUtcStamp(millis: number): string {
  const d = new Date(millis);
  const pad = (n: number) => n.toString().padStart(2, "0");
  return (
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`
  );
}

/** Luogo dell'evento: sala del corso (se valorizzata) + indirizzo palestra. */
export function eventLocation(sala?: string | null): string {
  const trimmed = sala?.trim();
  return trimmed ? `${trimmed} — ${GYM_ADDRESS}` : GYM_ADDRESS;
}

/** Testo della descrizione dell'evento (condiviso tra link Google e `.ics`). */
export function eventDescription(): string {
  return EVENT_DESCRIPTION;
}

function projectId(): string {
  return (
    process.env.GCLOUD_PROJECT ??
    process.env.GOOGLE_CLOUD_PROJECT ??
    FALLBACK_PROJECT_ID
  );
}

/**
 * Base URL della function `courseIcs`, risolta a runtime: prod, staging ed
 * emulatore producono ognuno il proprio link senza configurazione aggiuntiva.
 * `CALENDAR_ICS_BASE_URL` permette l'override (es. dominio custom in futuro).
 */
export function icsBaseUrl(): string {
  const override = process.env.CALENDAR_ICS_BASE_URL?.trim();
  if (override) return override;

  const project = projectId();
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    return `http://127.0.0.1:${ICS_EMULATOR_PORT}/${project}/${ICS_REGION}/${ICS_FUNCTION_NAME}`;
  }
  return `https://${ICS_REGION}-${project}.cloudfunctions.net/${ICS_FUNCTION_NAME}`;
}

/** Link al file `.ics` del corso (Apple Calendar, Outlook, altri client). */
export function icsUrl(courseId: string): string {
  return `${icsBaseUrl()}?courseId=${encodeURIComponent(courseId)}`;
}

export interface CalendarEventArgs {
  courseName: string;
  startMillis: number;
  endMillis: number;
  sala?: string | null;
}

/** Deeplink "crea evento" di Google Calendar. */
export function googleCalendarUrl(args: CalendarEventArgs): string {
  const params = new URLSearchParams({
    action: "TEMPLATE",
    text: args.courseName,
    dates: `${formatUtcStamp(args.startMillis)}/${formatUtcStamp(args.endMillis)}`,
    details: EVENT_DESCRIPTION,
    location: eventLocation(args.sala),
  });
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/**
 * Escaping di un URL per l'uso in un attributo HTML: gli `&` dei query string
 * vanno scritti `&amp;`, altrimenti i client email piu' severi troncano l'href.
 */
export function htmlAttr(url: string): string {
  return url.replace(/&/g, "&amp;");
}

/**
 * Blocco HTML con i due bottoni "aggiungi al calendario".
 * Tabelle e `background-color` sul `<td>` (non `<div>`): Outlook ignora il
 * border-radius sui div e non renderizza i bottoni a blocchi.
 */
export function calendarButtonsHtml(urls: {
  googleUrl: string;
  icsUrl: string;
}): string {
  return `
              <!-- Aggiungi al calendario -->
              <table cellpadding="0" cellspacing="0" style="margin: 20px 0;">
                <tr>
                  <td style="background-color: #6077F6; border-radius: 8px;">
                    <a href="${htmlAttr(urls.googleUrl)}" target="_blank"
                       style="display: inline-block; padding: 12px 20px; color: #ffffff; font-size: 15px; font-weight: 600; text-decoration: none;">
                      📅 Aggiungi a Google Calendar
                    </a>
                  </td>
                  <td style="width: 12px;">&nbsp;</td>
                  <td style="border: 1px solid #6077F6; border-radius: 8px;">
                    <a href="${htmlAttr(urls.icsUrl)}" target="_blank"
                       style="display: inline-block; padding: 12px 20px; color: #6077F6; font-size: 15px; font-weight: 600; text-decoration: none;">
                      🍎 Apple / Outlook / altro
                    </a>
                  </td>
                </tr>
              </table>`;
}

/** Entrambi gli URL per un corso, in un colpo solo (usato dai call-site email). */
export function calendarUrlsForCourse(
  courseId: string,
  args: CalendarEventArgs
): { googleUrl: string; icsUrl: string } {
  return { googleUrl: googleCalendarUrl(args), icsUrl: icsUrl(courseId) };
}
