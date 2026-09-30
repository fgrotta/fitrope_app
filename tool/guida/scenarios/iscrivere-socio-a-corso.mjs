// Guida: assets/guida/iscrivere-socio-a-corso.md
import { nextMonday } from '../lib/firestore.mjs';

export default async function (g, { db }) {
  // "Open PIENO" del seed ha 2 iscritti solo nel contatore: due iscrizioni
  // vere lo rendono un corso pieno normale, con Mario in lista d'attesa.
  await db.patch('users/abbonato-test', { courses: ['open-pieno'] });
  await db.patch('users/prova-test', { courses: ['open-pieno'] });

  const lunedi = nextMonday();
  const martedi = new Date(lunedi);
  martedi.setDate(lunedi.getDate() + 1);
  const iscritti = () => g.page.getByRole('button', { name: /^Iscritti \d+ di \d+/ }).first();

  await g.login();
  await g.goTab('Calendario');
  await g.selectCalendarDay(lunedi);
  await g.tap(g.agendaRow('Open mattina'));
  await g.shot('01-aggiungi-iscritto', { highlight: 'Aggiungi iscritto' });
  await g.frame('aggiungi', { highlight: 'Aggiungi iscritto' });

  await g.tap('Aggiungi iscritto');
  await g.type('Cerca per nome o cognome', 'Paola');
  await g.shot('02-cerca-socio', { highlight: 'Aggiungi al corso' });
  await g.frame('aggiungi', { highlight: 'Aggiungi al corso' });
  await g.tap('Aggiungi al corso');
  // Dopo l'iscrizione la lista si ricarica e la card torna chiusa.
  await g.waitText('9 liberi');
  await g.tap(g.agendaRow('Open mattina'));
  await g.frame('aggiungi', { highlight: iscritti() });

  await g.tap(iscritti());
  await g.dump('iscritti');
  await g.shot('03-iscritti', { highlight: 'Rimuovi iscrizione' });
  await g.frame('aggiungi', { highlight: 'Rimuovi iscrizione' });
  await g.tap('Rimuovi iscrizione');
  await g.shot('04-rimuovi', { highlight: g.dialogButton('Rimuovi') });
  await g.tap(g.dialogButton('Rimuovi'));
  await g.waitText('Utente rimosso con successo dal corso');

  // --- Lista d'attesa
  await g.selectCalendarDay(martedi);
  await g.tap(g.agendaRow('Open PIENO'));
  await g.tap(iscritti());
  await g.dump('attesa');
  await g.shot('05-lista-attesa', { highlight: "Rimuovi dalla lista d'attesa" });
}
