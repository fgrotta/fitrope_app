// Guida: assets/guida/problemi-app.md
import { nextMonday } from '../lib/firestore.mjs';

export default async function (g, { db }) {
  // Mario non ha ancora accettato il regolamento.
  await db.patch('users/mensile-test', { regolamentoAccettatoIl: null });
  const lunedi = nextMonday();

  // --- Il socio: il regolamento si accetta alla prima prenotazione
  await g.login({ email: 'mensile@test.it', password: 'test1234' });
  await g.goTab('Calendario');
  await g.selectCalendarDay(lunedi);
  await g.tap(g.agendaRow('Open mattina').getByRole('button', { name: 'Prenotati', exact: true }));
  await g.waitText('Regolamento della Palestra');
  await g.dump('regolamento');
  await g.shot('02-regolamento', {
    highlight: g.page.getByRole('group', { name: /^Ho letto e accetto/ }),
  });

  // --- L'Admin simula un socio che non riesce a prenotare
  await g.login();
  await g.openUser('Paola Pacchetto');
  await g.tap('Simula utente');
  await g.tap(g.dialogButton('Avvia simulazione'));
  await g.waitFor(g.tab('Calendario'), 30000);
  await g.goTab('Calendario');
  await g.selectCalendarDay(lunedi);
  await g.dump('simulazione');
  await g.shot('01-simula-abbonamento-scaduto', {
    highlight: g.agendaRow('Open mattina').getByRole('button').first(),
  });
}
