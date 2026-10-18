// Template certificati con layout condiviso delle email applicative.
import { emailShell, escapeHtml } from "./email/layout";

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
  return emailShell({ title: "Scadenza certificato medico", bodyHtml: textToHtml(reminderText(firstName)) });
}

export function certificateExpiryTodayBody(firstName: string): string {
  return emailShell({ title: "Certificato medico in scadenza", bodyHtml: textToHtml(expiryTodayText(firstName)) });
}

export function certificateReminderPreheader(): string {
  return "Mancano circa 10 giorni alla scadenza del tuo certificato medico.";
}

export function certificateExpiryTodayPreheader(): string {
  return "Oggi è l'ultimo giorno di validità del tuo certificato medico.";
}
