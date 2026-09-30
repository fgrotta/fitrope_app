// Guida: assets/guida/correggi-conteggio.md
import { nextMonday } from '../lib/firestore.mjs';

export default async function (g) {
  // "Open PIENO" del seed: il contatore dice 2 iscritti, ma nessun socio ha
  // davvero il corso. È esattamente il caso da correggere.
  const martedi = nextMonday();
  martedi.setDate(martedi.getDate() + 1);

  await g.login();
  await g.goTab('Calendario');
  await g.selectCalendarDay(martedi);
  await g.shot('01-riga-pieno', { highlight: g.agendaRow('Open PIENO') });
  await g.tap(g.agendaRow('Open PIENO'));
  const correggi = g.button('Correggi conteggio iscritti');
  await g.shot('02-icona', { highlight: correggi });
  await g.frame('correzione', { highlight: correggi });
  await g.tap(correggi);
  await g.shot('03-dialog', { highlight: g.dialogButton('Correggi') });
  await g.frame('correzione', { highlight: g.dialogButton('Correggi') });
  await g.tap(g.dialogButton('Correggi'));
  await g.waitText('Conteggio iscritti aggiornato con successo');
  await g.shot('04-corretto');
  await g.frame('correzione');
}
