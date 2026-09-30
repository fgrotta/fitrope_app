// Guida: assets/guida/pacchetti-ingressi.md
import { daysFromNow } from '../lib/firestore.mjs';

export default async function (g, { db }) {
  // Alba ha due pacchetti da 10 ingressi (Open e PT). Il seed non le mette
  // la versione del modello: senza, il dettaglio mostra anche il vecchio
  // riquadro "Piano di Iscrizione", che qui è solo rumore.
  await db.patch('users/abbonato-test', { subscriptionModelVersion: 2 });
  const subs = await db.where('subscriptions', 'userId', 'abbonato-test');
  const open = subs.find((s) => s.data.planKey === 'open_10i_3m');
  const pt = subs.find((s) => s.data.planKey === 'pt_10i_3m');
  // Stessa scadenza = ordine instabile nell'elenco. Col PT che scade prima,
  // l'Open (scadenza più lontana) è sempre il primo.
  await db.patch(`subscriptions/${pt.id}`, { endDate: daysFromNow(60, 23) });

  await g.login();
  await g.openUser('Alba Abbonata');
  const modificaOpen = () => g.page.getByRole('button', { name: 'Modifica', exact: true }).first();
  const residui = g.page.getByRole('dialog').or(g.page.getByRole('alertdialog')).getByRole('textbox');
  await g.shot('01-pacchetti', { highlight: modificaOpen() });

  // Oltre i 10 del pacchetto: nessun tetto.
  await g.tap(modificaOpen());
  await g.type(residui, '12');
  await g.shot('02-ingressi-residui', { highlight: residui });
  await g.tap(g.dialogButton('Salva'));
  await g.waitText('Abbonamento modificato');

  // A zero: Esaurito.
  await g.tap(modificaOpen());
  await g.type(residui, '0');
  await g.tap(g.dialogButton('Salva'));
  await g.waitText('Abbonamento modificato');
  await g.waitText('Esaurito');
  await g.shot('03-esaurito');

  // Una prenotazione cambia gli ingressi mentre il dialog è aperto.
  await g.tap(modificaOpen());
  await g.type(residui, '5');
  await db.patch(`subscriptions/${open.id}`, { remainingEntries: 3 });
  await g.tap(g.dialogButton('Salva'));
  await g.waitText('Gli ingressi sono cambiati nel frattempo');
  await g.shot('04-ingressi-cambiati');
}
