// Template HTML delle email sulla scadenza del certificato medico.
// NB: queste email partono server-side (Cloud Function schedulata), dove
// `lib/services/email_templates.dart` non è raggiungibile. Il branding qui
// replica volutamente quello dei template Dart (header #6077F6, logo, footer).
// Un test "drift guard" verifica subject/footer.

const LOGO_URL =
  "https://app.fithousemonza.it/assets/assets/new_logo_only.png";

function emailHeader(title: string): string {
  return `
          <tr>
            <td style="background-color: #6077F6; padding: 24px 30px; text-align: center;">
              <img src="${LOGO_URL}" alt="Fit House" width="72"
                   style="display: block; margin: 0 auto 12px auto; border: 0; height: auto;" />
              <h1 style="color: #ffffff; margin: 0; font-size: 22px; font-weight: 600;">${title}</h1>
            </td>
          </tr>`;
}

function emailFooter(): string {
  return `
          <tr>
            <td style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">— Il team Fit House</p>
            </td>
          </tr>`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Converte testo semplice in HTML: i blocchi separati da righe vuote diventano
 * paragrafi <p>, i newline singoli dentro un blocco diventano <br/>.
 */
function textToHtml(text: string): string {
  return text
    .trim()
    .split(/\n\s*\n/)
    .map((block) => {
      const inner = block
        .split("\n")
        .map((line) => line.trim())
        .join("<br/>");
      return `<p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 16px 0;">${inner}</p>`;
    })
    .join("\n");
}

function shell(title: string, bodyHtml: string): string {
  return `<html>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">
${emailHeader(title)}
          <tr>
            <td style="padding: 30px;">
${bodyHtml}
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

function greeting(firstName: string): string {
  const name = firstName.trim();
  return name ? `Ciao ${escapeHtml(name)} 👋` : "Ciao 👋";
}

/** Testo dell'email inviata ~10 giorni prima della scadenza. */
function reminderText(firstName: string): string {
  return `${greeting(firstName)}

Ti avvisiamo che mancano circa 10 giorni alla scadenza del tuo certificato medico.

Per continuare a partecipare alle nostre classi è necessario avere un certificato medico sportivo per attività non agonistica in corso di validità.

✅ Se hai già rinnovato il certificato, puoi consegnarcene una copia anche prima della scadenza.

✅ Se invece devi ancora effettuare la visita, puoi farla presso il nostro centro convenzionato DNP Sport e Salute al costo di 30 €.

Per prenotare puoi contattare direttamente uno di questi numeri:
📞 393 824 1473
📞 334 948 2628

Il giorno della visita dovrai presentare un modulo che ti forniremo noi in reception.

Ti chiediamo gentilmente di farci sapere tramite WhatsApp quale soluzione hai scelto:
➡️ se provvederai autonomamente al rinnovo del certificato;
➡️ oppure se effettuerai la visita presso il nostro centro convenzionato.

Per qualsiasi dubbio o per organizzare tutto direttamente con noi, contatta la reception:
📞 FitHouse Monza: 3783075332

Grazie per la collaborazione e a presto! 💪😊

Team FitHouse`;
}

/** Testo dell'email inviata il giorno della scadenza (adattamento del precedente). */
function expiryTodayText(firstName: string): string {
  return reminderText(firstName)
    .replace(
      "Ti avvisiamo che mancano circa 10 giorni alla scadenza del tuo certificato medico.",
      "Ti avvisiamo che oggi è l'ultimo giorno di validità del tuo certificato medico."
    )
    .replace(
      "✅ Se hai già rinnovato il certificato, puoi consegnarcene una copia anche prima della scadenza.",
      "✅ Se hai già rinnovato il certificato, puoi consegnarcene una copia il prima possibile."
    );
}

export function certificateReminderSubject(): string {
  return "Il tuo certificato medico sta per scadere";
}

export function certificateExpiryTodaySubject(): string {
  return "Il tuo certificato medico scade oggi";
}

export function certificateReminderBody(firstName: string): string {
  return shell("Scadenza certificato medico", textToHtml(reminderText(firstName)));
}

export function certificateExpiryTodayBody(firstName: string): string {
  return shell("Certificato medico in scadenza", textToHtml(expiryTodayText(firstName)));
}
