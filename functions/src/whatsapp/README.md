# WhatsApp lezioni demo: rilascio in produzione

Cosa serve per portare in produzione il WhatsApp di promemoria delle lezioni di prova.
Il funzionamento del codice è descritto in `CLAUDE.md`, sezione "WhatsApp lezioni demo
(webhook Make)".

Stato verificato il 27/10/2026.

## Cosa fa

- **Un solo messaggio**: il promemoria della sera prima. Il cron
  `sendDemoLessonWhatsappReminders` gira ogni giorno alle 19:00 ora di Roma e scrive
  agli utenti di prova iscritti a una lezione del giorno dopo. All'iscrizione non parte
  nessun WhatsApp.
- **Un solo scenario Make**: webhook → modulo WhatsApp con il template di promemoria.
  Nessun router e nessun filtro.
- **Body inviato a Make**: `{numero_di_telefono, lezione, giorno_lezione, orario_lezione}`.
  Gli ultimi tre campi sono le variabili del template: `{{lezione}}` è il nome del corso,
  `{{giorno_lezione}}` ha il formato `28 Ottobre`, `{{orario_lezione}}` il formato `19:00`.
  Il nome dell'utente non viene inviato.
- **Nessuna chiave**: l'URL del webhook è l'unica credenziale. Chi lo conosce può far
  partire un WhatsApp, quindi va trattato come una password. Sta solo in Secret Manager
  (`MAKE_WEBHOOK_URL`) e non compare mai nei log.
- **Il testo del messaggio non è nel codice**: è il template approvato da Meta e scelto
  nel modulo WhatsApp dello scenario Make. Si cambia senza deploy.

## Dove siamo

| Cosa | Stato |
|---|---|
| Functions di produzione | Ferme alla linea `main` v1.2.7 (sette function). Il codice WhatsApp attuale non c'è ancora. |
| Function WhatsApp in produzione | `notifyDemoLessonBooked` e `sendTestDemoLessonWebhook`, deployate a mano il 04/09 da un branch mai integrato: vecchio payload, vecchio webhook e chiave in header. Nessun client le chiama. Nessun cron. |
| `MAKE_WEBHOOK_URL` | Aggiornato il 27/10 al webhook nuovo, sia in produzione sia su staging. Le function già deployate restano legate alla versione vecchia fino al prossimo deploy. |
| `MAKE_WEBHOOK_KEY` | Esiste solo in produzione. Il codice nuovo non lo dichiara più. |
| Modalità di produzione | `functions/.env.fit-rope-app-1f575` → `WHATSAPP_DEMO_MODE=test`: viene deployata solo la callable di prova. |
| Staging | Pronto per la prova: il secret esiste. Basta impostare le vars (vedi A.3). |
| `develop` rispetto a `main` | 119 commit avanti. |

Conseguenza: **WhatsApp non ha un rilascio a sé**. Le function vivono in
`functions/src/index.ts` insieme a tutto il resto e arrivano in produzione con il
rilascio di `develop`: modello corsi V2, callable enrollment, rules e migrazione dei dati.

## A. Fuori dal repo (bloccanti per `live`)

1. **Template di promemoria approvato da Meta**, categoria Utility, sul numero WhatsApp
   Business collegato a Make. Variabili: `{{lezione}}`, `{{giorno_lezione}}`, `{{orario_lezione}}`. Il numero
   non deve essere attivo nell'app WhatsApp: una volta migrato, dall'app non si può più
   usare.
2. **Scenario Make**:
   - "Redetermine data structure" sul webhook, inviando un payload attuale (per esempio
     dalla pagina Debug). Make impara lo schema dal primo payload ricevuto;
   - nel modulo WhatsApp, le tre variabili del template collegate ai campi omonimi del body e
     il destinatario collegato a `numero_di_telefono`;
   - le **notifiche di errore dello scenario** attive. Il webhook risponde sempre `200`:
     numero senza WhatsApp, template non approvato o credito esaurito si vedono solo in
     Make.
3. **Prova end-to-end su staging** con il proprio numero:
   - environment GitHub `staging` → `STAGING_WHATSAPP_ALLOWLIST=<tuo numero>`, poi
     `STAGING_WHATSAPP_DEMO_MODE=test`;
   - rilancia `staging.yml` (o fai un merge su `develop`);
   - login sul sito staging con `admin.develop@example.com` → pulsante Debug → sezione
     WhatsApp → "WhatsApp — promemoria lezione".

## B. Decisioni da prendere prima del `live`

- **Privacy.** Il cellulare dell'utente di prova esce verso Make e Meta, insieme a nome,
  giorno e orario della lezione.
  Verificare l'informativa privacy e il rapporto di trattamento con Make (DPA).
- **Opt-out.** Nell'app non esiste un flag per non ricevere WhatsApp: i flag
  `emailNotificationsEnabled` e `pushNotificationsEnabled` non governano questo canale.
  Oggi un utente di prova attivo con un cellulare valido lo riceve sempre. Se serve
  un opt-out, va aggiunto prima del `live`.
- **Costi.** Ogni promemoria è un template Utility a pagamento su Meta, più le
  operazioni Make. Il volume è al massimo un messaggio per lezione di prova.
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
# Callable della vecchia conferma all'iscrizione, che non esiste più.
# Nessun client la chiama, quindi cancellarla non ha impatto.
firebase functions:delete notifyDemoLessonBooked --project prod --region europe-west8
```

`sendTestDemoLessonWebhook` invece resta: il deploy la sostituisce con la versione
nuova, legata al webhook nuovo. Con `WHATSAPP_DEMO_MODE=test` il rilascio non manda
nessun messaggio da solo.

Dopo il deploy:

- `MAKE_WEBHOOK_KEY` non serve più: `firebase functions:secrets:destroy MAKE_WEBHOOK_KEY --project prod`;
- le versioni vecchie di `MAKE_WEBHOOK_URL` (webhook precedenti) si possono disattivare.
  Prima controlla con `gcloud secrets versions list MAKE_WEBHOOK_URL --project fit-rope-app-1f575`
  quale versione è la più recente, e disattiva solo le altre.

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
  messaggio ricevuto.

## E. Passaggio a `live` (PR separata)

1. PR che porta `functions/.env.fit-rope-app-1f575` a `WHATSAPP_DEMO_MODE=live`
   (aggiornando il commento del file e `CLAUDE.md`).
2. `firebase deploy --project prod --only functions`. Nasce il cron
   `sendDemoLessonWhatsappReminders` (ogni giorno alle 19:00 ora di Roma,
   `europe-west8`) per le lezioni del giorno dopo. `subscribeToCourse` non cambia.
3. **Orario del deploy.** Se deployi prima delle 19:00, il cron parte la sera stessa e
   scrive anche a chi si era iscritto a una lezione di domani prima del `live`. È voluto,
   ma va saputo.
4. Il destinatario deve essere un utente di prova attivo, con un cellulare valido,
   iscritto a un corso del giorno dopo che abbia `reminderEnabled` attivo.

## F. Monitoraggio

```bash
firebase functions:log --only sendDemoLessonWhatsappReminders --project prod
firebase functions:log --only sendTestDemoLessonWebhook --project prod
```

- `demoLessonWebhookLog/reminder_{userId}_{courseId}` registra l'esito di ogni invio.
  Gli stati `pending`/`unknown` (timeout, rete, 5xx) **non vengono reinviati**: controlla
  in Make prima di intervenire a mano.
- La history di Make e le notifiche di errore dello scenario.
- WhatsApp Manager di Meta: qualità del numero e stato del template. Meta può mettere in
  pausa un template segnalato dagli utenti.

## G. Stop di emergenza e rollback

- **Immediato, senza deploy: disattiva lo scenario Make.** Il cron continua a chiamare il
  webhook, ma il messaggio non parte. Attenzione: con lo scenario spento Make tiene in
  coda le richieste ricevute e le esegue alla riattivazione. Svuota la coda del webhook
  prima di riaccenderlo.
- **Solo il cron**: metti in pausa il job di Cloud Scheduler. Il nome esatto si legge con
  `gcloud scheduler jobs list --location europe-west8 --project fit-rope-app-1f575`, poi
  `gcloud scheduler jobs pause <job> --location europe-west8 --project fit-rope-app-1f575`.
- **Se l'URL del webhook trapela**: crea un webhook nuovo in Make, aggiorna il secret con
  `firebase functions:secrets:set MAKE_WEBHOOK_URL --project prod`, rideploya le
  Functions e cancella il webhook vecchio in Make.
- **Definitivo**: PR che riporta la modalità da `live` a `test`. Prima del deploy cancella
  a mano il cron, perché il deploy non interattivo si ferma davanti a function sparite
  dal sorgente:
  `firebase functions:delete sendDemoLessonWhatsappReminders --project prod --region europe-west8`.

## Checklist

- [ ] Template di promemoria approvato da Meta (A.1)
- [ ] Scenario Make: nuova struttura dati, parametri collegati, notifiche di errore (A.2)
- [ ] Prova end-to-end su staging (A.3)
- [ ] Decisi privacy/DPA, opt-out, costi, email certificati (B)
- [ ] `notifyDemoLessonBooked` cancellata in produzione (C)
- [ ] Rilascio di `develop` in produzione completato, in modalità `test` (C)
- [ ] `MAKE_WEBHOOK_KEY` distrutto e versioni vecchie di `MAKE_WEBHOOK_URL` disattivate (C)
- [ ] Prova dalla build di debug locale verso la produzione, sul proprio numero (D)
- [ ] PR `live` mergiata e Functions deployate, a un orario scelto (E)
- [ ] Prima sera del cron controllata nei log, in `demoLessonWebhookLog` e in Make (F)
