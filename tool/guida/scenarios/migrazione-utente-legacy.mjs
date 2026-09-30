// Guida: assets/guida/migrazione-utente-legacy.md
import { addMonths, daysFromNow } from '../lib/firestore.mjs';

export default async function (g, { db }) {
  // Mario (mensile legacy) scade tra 60 giorni: l'inizio ricostruito
  // cadrebbe nel futuro e la migrazione non sarebbe automatica. A 20 giorni
  // dalla fine diventa convertibile in automatico.
  await db.patch('users/mensile-test', { fineIscrizione: daysFromNow(20, 23) });
  // Pia senza ruolo: il caso "Normalizza profilo".
  await db.patch('users/prova-test', { role: '' });
  // Alba ha già un Open del nuovo modello: aggiungerle un vecchio mensile
  // Open produce il conflitto.
  await db.patch('users/abbonato-test', {
    tipologiaIscrizione: 'ABBONAMENTO_MENSILE',
    entrateSettimanali: 2,
    fineIscrizione: daysFromNow(20, 23),
    tipologiaCorsoTags: ['Open'],
  });

  await g.login();

  // --- Migrazione automatica
  await g.openUser('Mario Mensile');
  await g.waitText('Target:');
  await g.shot('01-automatica', { highlight: 'Migra automaticamente' });
  await g.frame('migrazione', { highlight: 'Migra automaticamente' });
  await g.tap('Migra automaticamente');
  await g.shot('02-conferma', { highlight: g.dialogButton('Migra') });
  await g.frame('migrazione', { highlight: g.dialogButton('Migra') });
  await g.tap(g.dialogButton('Migra'));
  await g.waitText('Abbonamento legacy migrato');
  await g.shot('03-migrato');
  await g.frame('migrazione');

  // --- Migrazione con piano scelto
  await g.openUser('Paola Pacchetto');
  await g.waitText('Piano target');
  const pianoTarget = g.page.getByRole('button', { name: /Piano target/ }).first();
  await g.tap(pianoTarget);
  await g.tap(g.option('Open 10 ingressi · 3 mesi'));
  const inizio = new Date();
  await g.pickDate(g.button('Data inizio'), inizio);
  await g.pickDate(g.button('Data fine'), addMonths(inizio, 3));
  await g.type('Ingressi residui', '5');
  await g.shot('04-piano-scelto', { highlight: 'Migra con piano scelto' });
  await g.tap('Migra con piano scelto');
  await g.tap(g.dialogButton('Migra'));
  await g.waitText('Abbonamento legacy migrato');

  // --- Profilo da normalizzare
  await g.openUser('Pia Prova');
  await g.waitText('Ruolo da normalizzare');
  await g.shot('05-normalizza', { highlight: 'Normalizza profilo' });
  await g.tap('Normalizza profilo');
  await g.waitText('Profilo normalizzato');

  // --- Conflitto
  await g.openUser('Alba Abbonata');
  await g.waitText('esiste già una subscription');
  await g.shot('06-conflitto', { highlight: g.text('esiste già una subscription') });
}
