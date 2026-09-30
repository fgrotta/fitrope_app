// Guida: assets/guida/corsi.md
import { daysFromNow } from '../lib/firestore.mjs';

export default async function (g) {
  const domani = daysFromNow(1);
  await g.login();
  await g.goTab('Calendario');
  await g.shot('01-calendario', { highlight: ['Crea nuovo corso', 'Corsi ricorrenti'] });

  // --- Nuovo corso
  await g.frame('crea-corso', { highlight: 'Crea nuovo corso' });
  await g.tap('Crea nuovo corso');
  await g.type('Nome corso', 'Pilates serale');
  await g.tap(g.page.getByRole('checkbox', { name: 'Pilates', exact: true }));
  await g.frame('crea-corso');
  await g.shot('02-nuovo-corso', { highlight: g.page.getByRole('group', { name: /^Tag descrittivo/ }) });
  await g.pickDate(g.button('Seleziona Data'), domani);
  await g.pickTime(g.button('Seleziona Ora'), 18, 30);
  await g.type('Numero massimo partecipanti', '10');
  await g.select('Trainer', 'Teo Trainer');
  await g.select('Sala', 'Sala 1');
  await g.frame('crea-corso', { highlight: g.page.getByRole('group', { name: /^Data e Ora/ }) });
  await g.shot('03-data-ora', { highlight: g.page.getByRole('group', { name: /^Data e Ora/ }) });
  await g.shot('04-trainer-sala-notifiche', {
    highlight: [g.dropdown('Trainer'), g.dropdown('Sala'), g.page.getByRole('group', { name: /^Notifiche e Lista/ })],
  });
  await g.frame('crea-corso', { highlight: 'Crea' });
  await g.tap('Crea');
  await g.waitText('Corso creato con successo');
  await g.frame('crea-corso');

  // --- Azioni sul corso
  await g.selectCalendarDay(domani);
  await g.tap(g.agendaRow('Pilates serale'));
  await g.frame('crea-corso');
  await g.shot('05-azioni-corso', {
    highlight: [g.button('Modifica corso'), g.button('Duplica corso'), g.button('Elimina corso')],
  });

  await g.tap('Duplica corso');
  await g.waitText('Duplica Corso');
  await g.shot('06-duplica', { highlight: g.page.getByRole('group', { name: /^Data e Ora/ }) });
  await g.tap('Annulla');

  // --- Corsi ricorrenti
  await g.tap('Corsi ricorrenti');
  await g.type('Nome corso', 'Yoga mattina');
  await g.tap(g.page.getByRole('checkbox', { name: 'Yoga', exact: true }));
  // L'ora di partenza è quella corrente: una fissa rende l'anteprima stabile.
  await g.pickTime(g.button('Seleziona Ora'), 7, 30);
  await g.type('Numero massimo partecipanti', '8');
  await g.select('Trainer', 'Teo Trainer');
  await g.select('Sala', 'Sala 2');
  await g.tap(g.page.getByRole('checkbox', { name: 'Lunedì', exact: true }));
  await g.tap(g.page.getByRole('checkbox', { name: 'Giovedì', exact: true }));
  await g.waitText('corsi verranno creati');
  await g.shot('07-ricorrenti', { highlight: g.page.getByRole('button', { name: /^Crea \d+ Corsi$/ }) });
  await g.tap('Annulla');

  // --- Eliminazione
  await g.selectCalendarDay(domani);
  await g.tap(g.agendaRow('Pilates serale'));
  await g.tap('Elimina corso');
  await g.shot('08-elimina', { highlight: g.dialogButton('Elimina') });
  await g.tap(g.dialogButton('Elimina'));
  await g.waitText('Corso cancellato con successo');
}
