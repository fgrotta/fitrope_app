# WhatsApp lezioni demo: rilascio in produzione

Cosa serve per portare in produzione i WhatsApp delle lezioni di prova (conferma
all'iscrizione e promemoria della sera prima). Il funzionamento del codice è
descritto in `CLAUDE.md`, sezione "WhatsApp lezioni demo (webhook Make)".

Stato verificato il 27/10/2026.

## Dove siamo

| Cosa | Stato |
|---|---|
| Functions di produzione | Ferme alla linea `main` v1.2.7 (sette function). L'iscrizione ai corsi è ancora client-side: la callable `subscribeToCourse`, dove si aggancia la conferma WhatsApp, in produzione **non esiste**. |
| Function WhatsApp in produzione | `notifyDemoLessonBooked` e `sendTestDemoLessonWebhook`, deployate a mano il 04/09 da un branch mai integrato. Nessun client le chiama. Nessun cron. |
| Secret in `fit-rope-app-1f575` | `MAKE_WEBHOOK_URL` e `MAKE_WEBHOOK_KEY` esistono (creati il 04/09). |
| Modalità di produzione | `functions/.env.fit-rope-app-1f575` → `WHATSAPP_DEMO_MODE=test`: verrebbe deployata solo la callable di prova. |
| `develop` rispetto a `main` | 119 commit avanti. |
| Staging | Prova possibile con la PR #56: var `STAGING_WHATSAPP_DEMO_MODE=test` più allowlist. |

Conseguenza: **WhatsApp non ha un rilascio a sé**. Le function vivono in
`functions/src/index.ts` insieme a tutto il resto, quindi arrivano in produzione con il
rilascio di `develop`: modello corsi V2, callable enrollment, rules e migrazione dei dati.

## A. Fuori dal repo: Meta e Make (bloccanti per `live`)

1. **Numero WhatsApp Business dedicato** su Cloud API. Non usare un numero già attivo
   nell'app WhatsApp: una volta migrato, dall'app non si può più usare.
2. **Due template di categoria Utility approvati da Meta**: conferma della prenotazione e
   promemoria. Parametri: `nome`, `corso`, `giorno`, `orario`.
3. **Scenario Make**:
   - "Get request headers" attivo e un filtro che lascia passare solo le richieste con
     l'header `Demo-Reminder` uguale al valore di `MAKE_WEBHOOK_KEY`;
   - "Redetermine data structure" sul webhook, inviando un payload attuale. Il campo
     `tipo` non c'era nel payload da cui Make ha imparato lo schema a settembre;
   - un Router su `tipo`: `conferma` va al template di conferma, `promemoria` a quello di
     promemoria;
   - le **notifiche di errore dello scenario** attive. Il webhook risponde sempre `200`:
     numero senza WhatsApp, template non approvato o credito esaurito si vedono solo in
     Make.
4. **Prova end-to-end su staging** con il proprio numero, per entrambi i `tipo`
   (pagina Debug, sezione WhatsApp).

## B. Decisioni da prendere prima del `live`

- **Privacy.** Il nome e il cellulare dell'utente di prova escono verso Make e Meta.
  Verificare l'informativa privacy e il rapporto di trattamento con Make (DPA).
- **Opt-out.** Nell'app non esiste un flag per non ricevere WhatsApp: i flag
  `emailNotificationsEnabled` e `pushNotificationsEnabled` non governano questo canale.
  Oggi un utente di prova attivo, con nome e cellulare validi, li riceve sempre. Se
  serve un opt-out, va aggiunto prima del `live`.
- **Costi.** Ogni messaggio è un template Utility a pagamento su Meta, più le
  operazioni Make. Il volume massimo è di due messaggi per lezione di prova.
- **Trasporto.** Si resta su Make (codice attuale) oppure si passa a Meta Cloud API
  diretto (PR #48, ancora aperta: espone gli esiti di consegna)? Cambiare dopo il
  `live` richiede un altro rilascio.
- **Email certificati** (non riguarda WhatsApp, ma blocca qualsiasi deploy Functions da
  `develop`). In produzione girano `sendCertificateExpiryEmails` e
  `sendTestCertificateEmail`, che su `develop` sono escluse dalla produzione. Il primo
  deploy deve cancellarle, e le email giornaliere dei certificati si fermano finché la
  feature non viene promossa. È una scelta di prodotto.

## C. Prerequisito: il rilascio di `develop` in produzione

Va seguito il rilascio completo: merge `develop` → `main`, version bump, Functions,
web su Hostinger, rules e migrazione dei dati. Procedura e vincoli d'ordine sono in
`docs/migrations/course-model-v2/RUNBOOK.md` e in `CLAUDE.md`.

Per la parte WhatsApp, prima del primo `firebase deploy --project prod --only functions`:

```bash
# Callable superata: la conferma ora parte server-side da subscribeToCourse.
# Nessun client la chiama, quindi cancellarla non ha impatto.
firebase functions:delete notifyDemoLessonBooked --project prod --region europe-west8
```

`sendTestDemoLessonWebhook` invece resta, e il deploy la sostituisce con la versione
nuova. Con `WHATSAPP_DEMO_MODE=test` il rilascio non manda nessun messaggio da solo.

## D. Verifica in produzione (modalità `test`)

La pagina Debug non entra nella build di produzione: `debugToolsEnabled` è falsa. Per una
prova serve una build di debug locale, che senza `USE_EMULATOR` parla con la produzione:

```bash
flutter run -d chrome   # login con un Admin → FAB "Debug email" → sezione WhatsApp
```

- In produzione **non c'è allowlist**: qualunque numero inserito riceve davvero il
  messaggio. Usa solo il tuo.
- È l'unica eccezione alla regola "QA mai in produzione": la callable di prova non legge
  né scrive iscrizioni o registro invii, e non tocca dati.
- Da controllare: risposta `ok` nello SnackBar, esecuzione nella history di Make,
  messaggio ricevuto. Ripeti per `conferma` e `promemoria`.

## E. Passaggio a `live` (PR separata)

1. PR che porta `functions/.env.fit-rope-app-1f575` a `WHATSAPP_DEMO_MODE=live`
   (aggiornando il commento del file e `CLAUDE.md`).
2. `firebase deploy --project prod --only functions`. Cosa cambia:
   - `subscribeToCourse` viene rideployata con i secret Make. Ogni iscrizione di un utente
     di prova (`isTrialUser`), anche quella fatta dallo staff, manda subito il WhatsApp
     di conferma;
   - nasce il cron `sendDemoLessonWhatsappReminders` (ogni giorno alle 19:00 ora di Roma,
     `europe-west8`) per le lezioni del giorno dopo. Salta chi ha già ricevuto la
     conferma nello stesso giorno e i corsi con `reminderEnabled` disattivato.
3. **Orario del deploy.** Se deployi prima delle 19:00, il cron parte la sera stessa:
   ricevono il promemoria anche gli utenti iscritti a una lezione di domani prima del
   `live`, che la conferma non l'hanno avuta. È voluto, ma va saputo.
4. Il destinatario deve essere un utente attivo, con nome e cellulare validi, iscritto a
   un corso futuro. Per il promemoria il corso deve avere `reminderEnabled` attivo.

## F. Monitoraggio

```bash
firebase functions:log --only sendDemoLessonWhatsappReminders --project prod
firebase functions:log --only subscribeToCourse --project prod
firebase functions:log --only sendTestDemoLessonWebhook --project prod
```

- `demoLessonWebhookLog/{kind}_{userId}_{courseId}` registra l'esito di ogni invio. Gli
  stati `pending`/`unknown` (timeout, rete, 5xx) **non vengono reinviati**: controlla in
  Make prima di intervenire a mano.
- La history di Make e le notifiche di errore dello scenario.
- WhatsApp Manager di Meta: qualità del numero e stato dei template. Meta può mettere in
  pausa un template segnalato dagli utenti.

## G. Stop di emergenza e rollback

- **Immediato, senza deploy: disattiva lo scenario Make.** Le function continuano a
  chiamare il webhook, ma il messaggio non parte. Attenzione: con lo scenario spento
  Make tiene in coda le richieste ricevute e le esegue alla riattivazione. Svuota la coda
  del webhook prima di riaccenderlo.
- **Solo il cron**: metti in pausa il job di Cloud Scheduler. Il nome esatto si legge con
  `gcloud scheduler jobs list --location europe-west8 --project fit-rope-app-1f575`, poi
  `gcloud scheduler jobs pause <job> --location europe-west8 --project fit-rope-app-1f575`.
- **Definitivo**: PR che riporta la modalità da `live` a `test`. Prima del deploy cancella
  a mano il cron, perché il deploy non interattivo si ferma davanti a function sparite
  dal sorgente:
  `firebase functions:delete sendDemoLessonWhatsappReminders --project prod --region europe-west8`.

## Checklist

- [ ] Numero dedicato e due template Utility approvati (A.1–A.2)
- [ ] Scenario Make: header, nuova struttura dati, router su `tipo`, notifiche di errore (A.3)
- [ ] Prova end-to-end su staging, entrambi i `tipo` (A.4)
- [ ] Decisi privacy/DPA, opt-out, costi, trasporto, email certificati (B)
- [ ] `notifyDemoLessonBooked` cancellata in produzione (C)
- [ ] Rilascio di `develop` in produzione completato, in modalità `test` (C)
- [ ] Prova dalla build di debug locale verso la produzione, sul proprio numero (D)
- [ ] PR `live` mergiata e Functions deployate, a un orario scelto (E)
- [ ] Prima sera del cron controllata nei log, in `demoLessonWebhookLog` e in Make (F)
