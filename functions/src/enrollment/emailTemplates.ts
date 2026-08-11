// Mirror server-side di lib/services/email_templates.dart.
// Tenere allineato manualmente: stesse stringhe/HTML del client.

const LOGO_URL =
  "https://app.fithousemonza.it/assets/assets/new_logo_only.png";

function emailHeader(title: string): string {
  return `
          <!-- Header con logo -->
          <tr>
            <td style="background-color: #6077F6; padding: 24px 30px; text-align: center;">
              <img src="${LOGO_URL}" alt="Fit House" width="72"
                   style="display: block; margin: 0 auto 12px auto; border: 0; height: auto;" />
              <h1 style="color: #ffffff; margin: 0; font-size: 22px; font-weight: 600;">
                ${title}
              </h1>
            </td>
          </tr>`;
}

function emailFooter(): string {
  return `
          <!-- Footer -->
          <tr>
            <td style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">
                — Il team Fit House
              </p>
            </td>
          </tr>`;
}

export function trialReminderSubject(courseName: string): string {
  return `Promemoria: la tua lezione di prova "${courseName}" è domani!`;
}

export function trialReminderBody(args: {
  courseName: string;
  courseDate: string;
  courseTime: string;
}): string {
  return `
<html>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">

${emailHeader("Promemoria lezione di prova")}

          <!-- Body -->
          <tr>
            <td style="padding: 30px;">
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
                      ${args.courseName}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> ${args.courseDate}
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> ${args.courseTime}
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

            </td>
          </tr>

${emailFooter()}

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
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

  return `
<html>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">

${emailHeader("Posto disponibile!")}

          <!-- Body -->
          <tr>
            <td style="padding: 30px;">
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
                      ${args.courseName}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> ${args.courseDate}
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> ${args.courseTime}
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #FF9800; font-weight: bold;">
                      ${spotsText}
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Iscriviti subito prima che il posto venga occupato!
              </p>

            </td>
          </tr>

${emailFooter()}

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
