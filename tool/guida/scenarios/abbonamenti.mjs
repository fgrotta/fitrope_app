// Guida: assets/guida/abbonamenti.md
export default async function (g) {
  await g.login();

  // Un socio nuovo con la Prova di partenza: l'assegnazione di un Open la
  // sostituisce, che è il caso più comune al banco.
  await g.goTab('Utenti');
  await g.tap('Crea Utente');
  await g.type('Nome *', 'Marco');
  await g.type('Cognome *', 'Rossi');
  await g.tap('Crea Utente');
  await g.waitText('Utente creato con successo');

  await g.openUser('Marco Rossi');
  await g.shot('01-assegna-vuota', { highlight: g.dropdown('Tipo') });
  await g.frame('assegnazione', { highlight: g.dropdown('Tipo') });
  await g.select('Tipo', 'Open');
  await g.frame('assegnazione', { highlight: g.dropdown('Modalita') });
  await g.select('Modalita', 'Frequenza settimanale');
  await g.frame('assegnazione', { highlight: g.dropdown('Variante') });
  await g.select('Variante', '2 volte/settimana');
  await g.frame('assegnazione', { highlight: g.dropdown('Durata') });
  await g.select('Durata', '1 mese');
  await g.waitText('La Prova verrà chiusa');
  await g.shot('02-assegna-compilata', { highlight: 'Assegna' });
  await g.frame('assegnazione', { highlight: 'Assegna' });
  await g.tap('Assegna');
  await g.waitText('Abbonamento assegnato');
  await g.shot('03-assegnato');
  await g.frame('assegnazione');

  // --- Elenco, Modifica
  await g.scroll(500);
  await g.shot('04-elenco', { highlight: ['Modifica', 'Revoca'] });
  await g.tap('Modifica');
  await g.dump('modifica');
  await g.shot('05-modifica', { highlight: g.dialogButton('Salva') });
  await g.select('Durata', '3 mesi');
  await g.tap(g.dialogButton('Salva'));
  await g.waitText('Abbonamento modificato');

  // --- Storico con i revocati
  await g.tap('Mostra tutti');
  await g.scroll(400);
  await g.shot('06-storico', { highlight: 'Nascondi revocati' });
  await g.tap('Nascondi revocati');

  // --- Sovrapposizione: stesso Open, stesse date
  await g.scroll(-1000);
  await g.tap('Assegna');
  await g.waitText('Esiste già un abbonamento');
  await g.shot('07-sovrapposizione');

  // --- Revoca
  await g.scroll(500);
  await g.tap('Revoca');
  await g.shot('08-revoca', { highlight: g.dialogButton('Revoca') });
  await g.tap(g.dialogButton('Revoca'));
  await g.waitText('Abbonamento revocato');
}
