// Template delle notifiche enrollment; layout condiviso in email/layout.ts.
import { calendarButtonsHtml } from "./calendarLinks";
import { emailShell, ctaButton, escapeHtml } from "../email/layout";

/** Righe "sala" della card dettagli: presente solo se il corso ha una sala. */
function salaRow(sala?: string | null): string {
  const trimmed = sala?.trim();
  if (!trimmed) return "";
  return `
                    <p style="margin: 4px 0 0 0; font-size: 14px; color: #555555;">
                      📍 <strong>Sala:</strong> ${escapeHtml(trimmed)}
                    </p>`;
}

export interface TrialEmailArgs {
  courseName: string;
  courseDate: string;
  courseTime: string;
  sala?: string | null;
  googleUrl: string;
  icsUrl: string;
}

export function trialConfirmationSubject(courseName: string): string {
  return `Iscrizione confermata: lezione di prova "${courseName}"`;
}

export function trialConfirmationBody(args: TrialEmailArgs): string {
  return emailShell({
    title: "Iscrizione confermata",
    bodyHtml: `
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                La tua iscrizione alla lezione di prova è confermata. Ti aspettiamo 💪
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      ${escapeHtml(args.courseName)}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> ${escapeHtml(args.courseDate)}
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> ${escapeHtml(args.courseTime)}
                    </p>${salaRow(args.sala)}
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Segna la lezione sul tuo calendario così non te la dimentichi:
              </p>

${calendarButtonsHtml({ googleUrl: args.googleUrl, icsUrl: args.icsUrl })}

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

${ctaButton("Apri Fit House")}
`,
  });
}

export function trialReminderSubject(courseName: string): string {
  return `Promemoria: la tua lezione di prova "${courseName}" è domani!`;
}

export function trialReminderBody(args: TrialEmailArgs): string {
  return emailShell({
    title: "Promemoria lezione di prova",
    bodyHtml: `
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ti ricordiamo che domani hai la tua lezione di prova! Ti aspettiamo 💪
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      ${escapeHtml(args.courseName)}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> ${escapeHtml(args.courseDate)}
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> ${escapeHtml(args.courseTime)}
                    </p>${salaRow(args.sala)}
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Non l'hai ancora messa in agenda? Fallo ora:
              </p>

${calendarButtonsHtml({ googleUrl: args.googleUrl, icsUrl: args.icsUrl })}

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

${ctaButton("Apri Fit House")}
`,
  });
}

export function waitlistSpotAvailableSubject(courseName: string): string {
  return `Posto disponibile nel corso "${courseName}"!`;
}

export function waitlistSpotAvailableBody(args: {
  courseName: string;
  courseDate: string;
  courseTime: string;
  spotsAvailable: number;
}): string {
  const spotsText =
    args.spotsAvailable === 1
      ? "1 posto disponibile"
      : `${args.spotsAvailable} posti disponibili`;

  return emailShell({
    title: "Posto disponibile!",
    bodyHtml: `
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Si è liberato un posto nel corso a cui eri in lista d'attesa!
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      ${escapeHtml(args.courseName)}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> ${escapeHtml(args.courseDate)}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> ${escapeHtml(args.courseTime)}
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #FF9800; font-weight: bold;">
                      ${spotsText}
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Il posto rimane disponibile per un tempo limitato: apri l'app per iscriverti.
              </p>

${ctaButton("Apri Fit House")}
`,
  });
}

export function trialConfirmationPreheader(courseName: string): string {
  return `Ti aspettiamo a "${courseName}": segna la lezione sul calendario.`;
}

export function trialReminderPreheader(courseName: string): string {
  return `Domani la tua lezione di prova "${courseName}".`;
}

export function waitlistSpotAvailablePreheader(courseName: string): string {
  return `Si è liberato un posto in "${courseName}": prenota dall'app.`;
}
