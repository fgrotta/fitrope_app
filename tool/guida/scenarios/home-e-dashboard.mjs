// Guida: assets/guida/home-e-dashboard.md
import { daysFromNow } from '../lib/firestore.mjs';

export default async function (g, { db }) {
  // Col seed le card Admin della Home sono vuote: qualche caso per riempirle.
  // Mario: certificato scaduto, abbonamento in scadenza tra 12 giorni.
  await db.patch('users/mensile-test', {
    certificatoScadenza: daysFromNow(-5),
    fineIscrizione: daysFromNow(12, 23),
  });
  // Alba: certificato in scadenza e regolamento mai accettato, con un corso
  // lunedì prossimo (sempre entro 7 giorni).
  await db.patch('users/abbonato-test', {
    certificatoScadenza: daysFromNow(9),
    regolamentoAccettatoIl: null,
    courses: ['open-lun'],
  });
  // Pia: prova valida, prenotata per lunedì.
  await db.patch('users/prova-test', {
    fineIscrizione: daysFromNow(20, 23),
    courses: ['open-lun'],
  });

  await g.login();
  await g.waitText('Certificati medici da verificare');
  await g.settle(2000);
  await g.shot('01-home-scadenze');
  await g.scroll(500);
  await g.shot('02-home-prove-regolamento');

  await g.goTab('Dashboard');
  await g.waitText('Dashboard analisi');
  await g.settle(2000);
  const inScadenza = g.page.getByRole('button', { name: /^Abbonamenti in scadenza \(prossimi 30 gg\)/ });
  await g.shot('03-dashboard', { highlight: g.page.getByRole('button', { name: /^Clienti con abbonamento attivo/ }) });
  await g.tap(inScadenza);
  await g.dump('drawer');
  await g.shot('04-elenco-csv', { highlight: 'Esporta in CSV' });
}
