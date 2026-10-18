# Email Fit House: stato e verifica operativa

## Prima fase

Notifiche prova, waitlist e certificati condividono il layout TypeScript in
`functions/src/email/layout.ts`. Le tre email enrollment di debug passano da
`sendTestEnrollmentEmail`: Admin-only, disponibile su emulatore/staging, con email
letta dal profilo server e allowlist applicata prima del contatto con OneSignal.
Reset password e verifica email continuano a partire da Firebase Auth.

## Rilievo DNS del 18 ottobre 2026

Query pubbliche tramite Google DNS-over-HTTPS. Il TTL di zona osservato per SPF
radice, MX e CNAME DKIM è 14400 secondi (4 ore); quello DMARC è 3600 secondi.

| Nome | Tipo | Valore osservato |
|---|---|---|
| `fithousemonza.it` | TXT SPF | `v=spf1 include:_spf.mail.hostinger.com include:spf.onesignal.email ~all` |
| `mail.fithousemonza.it` | TXT | Nessuna risposta TXT |
| `mail.fithousemonza.it` | MX | `10 mxb.onesignal.email.` |
| `os1._domainkey.mail.fithousemonza.it` | CNAME | `dkim1.3e2ec3d1-9c49-447d-8e87-adf045926cc1.onesignal.email.` |
| `os2._domainkey.mail.fithousemonza.it` | CNAME | `dkim2.3e2ec3d1-9c49-447d-8e87-adf045926cc1.onesignal.email.` |
| `_dmarc.fithousemonza.it` | TXT | `v=DMARC1; p=none` |

Ripetere, per ciascun nome e tipo:

```bash
curl --fail --silent --show-error 'https://dns.google/resolve?name=mail.fithousemonza.it&type=TXT'
```

## Verifiche locali del 18 ottobre 2026

- Build TypeScript e 745 test unitari Functions superati.
- 71 test di integrazione superati su Emulator Suite dedicata (progetto `demo-fitrope`).
- 747 test Flutter superati; analyze senza issue e controllo formattazione superato.

## Passaggi ancora da completare su dashboard e caselle reali

**Stato:** accesso alle dashboard OneSignal/Hostinger e header ricevuti non
disponibili durante lo sviluppo. Nessuna modifica DNS o mittente applicata;
nessuna prova di consegna reale effettuata. La presenza dei CNAME non certifica
`dkim=pass` e lo SPF mancante sul sottodominio non dimostra da solo la causa dello spam.

1. In OneSignal, Settings → Email, registrare lo stato del dominio e i valori
   esatti dei record richiesti. Confermare anche il sending domain, distinto
   dall'indirizzo From. Usare i valori della dashboard come fonte autoritativa.
2. Impostare nome mittente `Fit House`, From `noreply@fithousemonza.it`, reply-to
   `info@fithousemonza.it` e sending domain `mail.fithousemonza.it`, se confermato
   dalla configurazione verificata. Verificare che i default si applichino agli
   invii REST delle notifiche.
3. Da un invio mirato a una casella propria, annotare `Return-Path`, `d=` della
   firma DKIM e `Authentication-Results`. Evitare destinatari, link di azione e
   contenuti personali nei documenti versionati.
4. Aggiungere lo SPF di `mail` indicato da OneSignal. Il valore previsto dal piano
   originale è `v=spf1 include:spf.onesignal.email ~all`, da confermare in dashboard.
   Lo SPF radice non si eredita sul sottodominio; evitare nuovi include alla radice.
5. Creare e verificare la casella/alias `dmarc@fithousemonza.it`, poi aggiornare
   l'unico TXT DMARC a
   `v=DMARC1; p=none; rua=mailto:dmarc@fithousemonza.it; adkim=r; aspf=r`.
6. Rimuovere `include:spf.onesignal.email` dalla radice solo dopo aver verificato
   che gli invii OneSignal usino effettivamente il sottodominio nel Return-Path
   e che nessun flusso dipenda da OneSignal sul dominio radice. Conservare
   l'autorizzazione Hostinger. Registrare i valori precedenti per il ripristino.
7. Attendere i TTL precedenti e verificare di nuovo dashboard, DNS e header.
   Provare Gmail, Outlook/Hotmail e iCloud, registrando esito SPF/DKIM/DMARC e
   Inbox/Junk. Autenticazione corretta e arrivo in Inbox sono risultati distinti.

| Verifica | Stato |
|---|---|
| Dominio verificato nella dashboard OneSignal | Da rilevare |
| Mittente e reply-to effettivi | Da rilevare |
| Return-Path e dominio DKIM | Da rilevare |
| SPF/DKIM/DMARC sulle email ricevute | Da verificare |
| Consegna Gmail / Outlook / iCloud | Da verificare |
| Report DMARC ricevuti | Da verificare dopo configurazione |

Mantenere `p=none` durante l'osservazione iniziale. Un eventuale passaggio a
`quarantine` richiede una valutazione separata dei report.

## QA applicativa e rilascio

- La QA ordinaria usa un trasporto finto nei test. I test della callable reale
  si fermano prima dell'invio, su login, ruolo o validazione; il percorso positivo
  usa Firestore emulator e trasporto iniettato. Nessuna chiave OneSignal reale serve.
- Un emulatore avviato con il progetto PRD può leggere secret PRD: per le prove
  manuali predisporre `.secret.local` con una chiave OneSignal fittizia. Gli invii
  sintetici non devono raggiungere OneSignal PRD con una chiave valida.
- In staging clone mode restano attivi il guard sugli attori e l'allowlist sui
  destinatari. Una soppressione non deve produrre successo nella pagina debug.
- La callable di debug non viene esportata in produzione. Staging distribuisce
  prima Functions e poi web; lo smoke test richiede `sendTestEnrollmentEmail`.
  Le notifiche di produzione ricevono layout e preheader col deploy Functions.
- Dopo il merge verso `develop`, verificare i gate e lo smoke test staging.
  Il deploy di produzione segue il normale rilascio separato del progetto.

Riferimenti: [configurazione email OneSignal](https://documentation.onesignal.com/docs/en/email-setup),
[API email OneSignal](https://documentation.onesignal.com/reference/email).
