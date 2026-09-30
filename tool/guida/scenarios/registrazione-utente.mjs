// Guida: assets/guida/registrazione-utente.md
export default async function (g) {
  // --- Registrazione autonoma del socio (da disconnessi)
  await g.shot('05-benvenuto-registrati', { highlight: 'Registrati' });
  await g.tap('Registrati');
  await g.type('Inserisci la tua email', 'giulia.verdi@example.com');
  await g.type('Inserisci la password', 'test1234');
  await g.type('Conferma la password', 'test1234');
  await g.type('Inserisci il tuo nome', 'Giulia');
  await g.type('Inserisci il tuo cognome', 'Verdi');
  await g.type('Inserisci il tuo numero di telefono', '3331234567');
  await g.tap(g.page.getByRole('checkbox').first());
  await g.scroll(400);
  await g.shot('06-registrazione-compilata', { highlight: 'Registrati' });
  await g.tap('Registrati');
  await g.waitText('Email di conferma inviata!');
  await g.shot('07-email-conferma');

  // --- Crea Utente dall'Admin
  await g.login();
  await g.goTab('Utenti');
  await g.shot('01-utenti-crea-utente', { highlight: 'Crea Utente' });
  await g.frame('crea-utente', { highlight: 'Crea Utente' });
  await g.tap('Crea Utente');
  await g.frame('crea-utente');
  await g.type('Nome *', 'Luca');
  await g.type('Cognome *', 'Bianchi');
  await g.type('Numero di Telefono (opzionale)', '3471234567');
  await g.type('Email (opzionale)', 'luca.bianchi@example.com');
  await g.frame('crea-utente', { highlight: g.dropdown('Piano iniziale *') });
  await g.select('Piano iniziale *', 'Open 2 volte/sett · 1 mese', {
    before: async () => {
      await g.shot('02-piano-iniziale');
      await g.frame('crea-utente');
    },
  });
  await g.shot('03-form-compilato', { highlight: 'Crea Utente' });
  await g.frame('crea-utente', { highlight: 'Crea Utente' });
  await g.tap('Crea Utente');
  await g.waitText('Utente creato');
  await g.shot('04-utente-creato');
  await g.frame('crea-utente');
}
