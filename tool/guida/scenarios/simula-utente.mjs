// Guida: assets/guida/simula-utente.md
import { nextMonday } from '../lib/firestore.mjs';

export default async function (g) {
  await g.login();
  await g.goTab('Utenti');
  await g.searchUsers('Mario');
  const occhio = g.userRow('Mario Mensile').getByRole('button', { name: 'Simula utente', exact: true });
  await g.shot('01-lista-simula', { highlight: occhio });
  await g.frame('simulazione', { highlight: occhio });
  await g.tap(occhio);
  await g.shot('02-conferma', { highlight: g.dialogButton('Avvia simulazione') });
  await g.frame('simulazione', { highlight: g.dialogButton('Avvia simulazione') });
  await g.tap(g.dialogButton('Avvia simulazione'));
  // In simulazione il rail perde Utenti e Dashboard: 2 schede invece di 4.
  await g.waitFor(g.page.getByRole('button', { name: /^Home Scheda 1 di 2/ }), 30000);
  await g.settle(1500);
  await g.shot('03-home-simulata', { highlight: g.simulationExit() });
  await g.frame('simulazione');

  await g.goTab('Calendario');
  await g.selectCalendarDay(nextMonday());
  const prenotati = g.agendaRow('Open mattina').getByRole('button', { name: 'Prenotati', exact: true });
  await g.frame('simulazione', { highlight: prenotati });
  await g.tap(prenotati);
  await g.waitText('Modalità simulazione: azione non eseguita');
  await g.shot('04-sola-lettura');
  await g.frame('simulazione');

  await g.frame('simulazione', { highlight: g.simulationExit() });
  await g.exitSimulation();
  await g.waitFor(g.tab('Utenti'), 30000);
  await g.frame('simulazione');
}
