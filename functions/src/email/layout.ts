// Header, colori e footer condivisi da tutte le email applicative Fit House.
export const BRAND_NAME = "Fit House";
export const APP_URL = "https://app.fithousemonza.it/";
export const LOGO_URL = `${APP_URL}assets/assets/new_logo_only.png`;
const PRIMARY = "#6077F6";

export function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

export function ctaButton(label: string, href: string = APP_URL): string {
  return `
              <table cellpadding="0" cellspacing="0" style="margin: 20px 0;">
                <tr>
                  <td style="background-color: ${PRIMARY}; border-radius: 8px;">
                    <a href="${escapeHtml(href)}" target="_blank"
                       style="display: inline-block; padding: 12px 24px; color: #ffffff; font-size: 15px; font-weight: 600; text-decoration: none;">
                      ${escapeHtml(label)}
                    </a>
                  </td>
                </tr>
              </table>`;
}

/** bodyHtml contiene il markup dei template; i valori dinamici vanno escapati. */
export function emailShell(args: { title: string; bodyHtml: string; footerNote?: string }): string {
  const note = args.footerNote
    ? `<p class="footer-note" style="color: #999999; font-size: 11px; margin: 8px 0 0 0;">${escapeHtml(args.footerNote)}</p>`
    : "";
  return `<html lang="it">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; background-color: #ffffff; border-radius: 12px; overflow: hidden;">
          <tr>
            <td style="background-color: ${PRIMARY}; padding: 24px 30px; text-align: center;">
              <img src="${LOGO_URL}" alt="${BRAND_NAME}" width="72"
                   style="display: block; margin: 0 auto 12px auto; border: 0; height: auto;" />
              <h1 style="color: #ffffff; margin: 0; font-size: 22px; font-weight: 600;">${escapeHtml(args.title)}</h1>
            </td>
          </tr>
          <tr>
            <td style="padding: 30px;">
${args.bodyHtml}
            </td>
          </tr>
          <tr>
            <td style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">— Il team ${BRAND_NAME}</p>${note}
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
