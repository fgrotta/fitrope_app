// Guida: assets/guida/presenze.md
//
// L'appello si apre da 30' prima dell'inizio: il corso "Open mattina" di oggi
// del seed viene spostato a 5' fa, con tre soci iscritti. Alba ha già fatto
// da sola "Sono in sala" (doc presenza + contatore scritti come farebbe il
// server), così l'immagine mostra anche la didascalia "check-in del socio".

export default async function (g, { db }) {
  const now = new Date();
  // Mai prima della mezzanotte: il corso deve restare nel giorno mostrato.
  const midnight = new Date(now);
  midnight.setHours(0, 0, 0, 0);
  const start = new Date(Math.max(now.getTime() - 5 * 60000, midnight.getTime()));
  const end = new Date(start.getTime() + 60 * 60000);

  await db.patch('courses/oggi-open-am', {
    startDate: start,
    endDate: end,
    subscribed: 3,
    attendance: { lastMarkedAt: now, lastMarkedBy: 'abbonato-test', presentCount: 1 },
  });
  for (const uid of ['abbonato-test', 'mensile-test', 'pacchetto-test']) {
    await db.patch(`users/${uid}`, { courses: ['oggi-open-am'] });
  }
  await db.patch('attendance/oggi-open-am_abbonato-test', {
    courseId: 'oggi-open-am',
    userId: 'abbonato-test',
    courseStartMillis: start.getTime(),
    present: true,
    source: 'self',
    markedBy: 'abbonato-test',
    markedAt: now,
    updatedAt: now,
  });

  const iscritti = () => g.page.getByRole('button', { name: /^Iscritti \d+ di \d+/ }).first();
  // La spunta ha lo stato "toggled": sul web il ruolo è `switch`, non `button`.
  const spunta = (nome, stato) =>
    g.page.getByRole('switch', { name: `${nome}: ${stato}`, exact: true }).first();
  const mario = (stato) => spunta('Mario Mensile', stato);
  const paola = (stato) => spunta('Paola Pacchetto', stato);

  await g.login();
  // Il calendario si apre su oggi, che è il giorno del corso.
  await g.goTab('Calendario');
  await g.tap(g.agendaRow('Open mattina'));
  await g.shot('01-corso', { highlight: iscritti() });
  await g.frame('appello', { highlight: iscritti() });

  await g.tap(iscritti());
  await g.waitText('1 su 3 presenti');
  await g.dump('appello');
  await g.shot('02-appello', { highlight: mario('non segnato') });
  await g.frame('appello', { highlight: mario('non segnato') });

  await g.tap(mario('non segnato'));
  await g.waitFor(mario('presente'));
  await g.waitText('2 su 3 presenti');
  await g.frame('appello', { highlight: paola('non segnato') });

  await g.tap(paola('non segnato'));
  await g.waitFor(paola('presente'));
  await g.tap(paola('presente'));
  await g.waitFor(paola('assente'));
  await g.shot('03-segnati', { highlight: [mario('presente'), paola('assente')] });
  await g.frame('appello', { highlight: [mario('presente'), paola('assente')] });
}
