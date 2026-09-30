// Guida: assets/guida/gestione-utente.md
import { formatDate } from '../lib/helpers.mjs';
import { daysFromNow } from '../lib/firestore.mjs';

export default async function (g) {
  await g.login();

  // --- Modifica anagrafica, ruolo e certificato
  await g.openUser('Mario Mensile');
  await g.shot('01-dettaglio', { highlight: 'Modifica profilo' });
  await g.tap('Modifica profilo');
  await g.scroll(600);
  await g.dump('modifica');
  await g.shot('02-modifica', { highlight: 'Salva modifiche' });
  await g.tap(g.button('User'));
  await g.shot('03-ruolo');
  await g.tap(g.option('User'));
  const certificato = daysFromNow(365);
  const attuale = g.page.getByRole('button', { name: /^\d\d\/\d\d\/\d{4}$/ }).last();
  await g.pickDate(attuale, certificato, {
    before: () => g.shot('04-certificato'),
  });
  await g.waitText(formatDate(certificato));
  await g.tap('Salva modifiche');
  await g.waitText('Utente aggiornato con successo');
  await g.shot('05-salvato');

  // --- Reset password
  await g.openUser('Alba Abbonata');
  await g.tap('Invia Email Reset Password');
  await g.shot('06-reset-password', { highlight: g.dialogButton('Invia Email') });
  await g.tap(g.dialogButton('Invia Email'));
  await g.waitText('Email di reset password inviata');

  // --- Disattiva / Attiva
  await g.goTab('Utenti');
  await g.searchUsers('Paola');
  const disattiva = g.userRow('Paola Pacchetto').getByRole('button', { name: 'Disattiva', exact: true });
  await g.shot('07-lista-disattiva', { highlight: disattiva });
  await g.tap(disattiva);
  await g.shot('08-conferma-disattiva', { highlight: g.dialogButton('Disattiva') });
  await g.tap(g.dialogButton('Disattiva'));
  await g.waitText('Utente disattivato con successo');
  await g.select('Stato', 'Solo disattivati');
  await g.shot('09-disattivati', { highlight: 'Attiva' });

  // --- Aggiungere l'email a un utente che non ce l'ha
  await g.searchUsers('');
  await g.select('Stato', 'Solo attivi');
  await g.tap('Crea Utente');
  await g.type('Nome *', 'Sara');
  await g.type('Cognome *', 'Neri');
  await g.tap('Crea Utente');
  await g.waitText('Utente creato con successo');
  await g.openUser('Sara Neri');
  await g.tap('Modifica profilo');
  await g.scroll(600);
  const email = g.page.getByRole('textbox').nth(3);
  await g.type(email, 'sara.neri@example.com');
  await g.shot('10-aggiungi-email', { highlight: email });
  await g.tap('Salva modifiche');
  await g.waitText('email di reset inviata');
  await g.shot('11-email-aggiunta');
}
