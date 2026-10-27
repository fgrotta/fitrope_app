# Runbook di rilascio Staging → PRD

Procedura operativa per portare in produzione la versione verificata su staging.
Il primo rilascio di `develop` in PRD non è un semplice deploy: la produzione è
ferma a `main` v1.2.7 (client che scrive direttamente su Firestore, 7 Functions,
nessuna rules versionata), mentre `develop` sposta iscrizioni, abbonamenti e
provisioning nelle callable, introduce rules strette e richiede la migrazione
batch del modello corsi/abbonamenti V2.

La sequenza segue il
[runbook della migrazione V2, sezione 16](../migrations/course-model-v2/RUNBOOK.md#16-completare-il-rollout-prd):
Functions prima, poi migrazione, poi web e rules **nella stessa finestra di
manutenzione**. Questo documento aggiunge ciò che il runbook di migrazione non
copre (inventario Functions, configurazione servizi, Hostinger, decisioni di
prodotto) e rimanda a esso per i comandi della migrazione, senza duplicarli.

> **Stato live rilevato il 27 ottobre 2026.** Gli inventari cloud cambiano nel
> tempo: ripetere i controlli indicati in questo runbook prima di ogni rilascio.
> Non usare i numeri di questa fotografia come criterio permanente.

## Differenze tra gli ambienti

| Area | Staging | PRD |
|---|---|---|
| Firebase | `fit-rope-staging` (alias `staging`) | `fit-rope-app-1f575` (alias `prod`) |
| Codice | `develop`, deploy automatico a ogni push (`staging.yml`) | `main` v1.2.7, deploy manuale |
| Auth e Firestore | Progetto separato; oggi in modalità clone (vedi sotto) | Dati reali e autenticazione utenti attivi |
| Functions | 22 function live, `nodejs22`, principalmente `europe-west8` | 7 function live, tra cui 4 assenti dal codice di `develop` (vedi sotto) |
| Web | GitHub Pages, `APP_ENV=staging`, config Firebase da GitHub `vars`, branding TEST | Hostinger, build e upload manuali, config Firebase PRD nel repository |
| Rules | Il workflow in modalità clone genera rules limitate a cinque UID QA | Rules live **non versionate**: `firestore.rules` non esiste su `main` |
| Indici Firestore | Nessun indice composito o override | Nessun indice composito o override |
| Env Functions | `.env.fit-rope-staging` generato dal workflow (`APP_ENV=staging`, allowlist, clone) | `functions/.env.fit-rope-app-1f575` versionato: solo `WHATSAPP_DEMO_MODE=test`, **mai** `APP_ENV` |
| Email certificati | `certificateEmailsDaily` (08:00 Roma, `europe-west8`), filtrata dall'allowlist | `sendCertificateExpiryEmails` di `main` (09:00 Roma, `europe-west1`), invii reali |
| Backup Firestore | Nessuna function di backup | `firestoreBackupDaily` / `firestoreBackupDailyCheck` nascono con il primo deploy di `develop` |
| WhatsApp demo | Var `STAGING_WHATSAPP_DEMO_MODE` (`off`/`test`) + allowlist numeri | `test`: solo la callable di prova Admin |
| OneSignal | Stessa app OneSignal di PRD (appId hardcoded in `lib/main.dart`); invii filtrati dalla allowlist | Invii effettivi agli utenti |

### Attenzione: modalità clone staging

Il workflow `.github/workflows/staging.yml` imposta attualmente
`STAGING_CLONE_MODE=true`, salta il seed sintetico e pubblica rules dedicate ai
cinque UID QA. Le callable protette rifiutano gli altri UID. Questa
configurazione è per una prova di clone, non per il normale QA staging.

Prima di usare staging come gate di rilascio:

1. verificare con il responsabile dei dati se il Firestore contiene dati derivati
   da PRD; la sola configurazione clone non prova quali documenti siano presenti;
2. se il clone è presente, conservarne gli artefatti solo nelle destinazioni
   private previste, quindi ripristinare il dataset sintetico e le rules standard;
3. aggiornare e revisionare il workflow: al momento imposta
   `STAGING_CLONE_MODE=true` in modo statico sia per il deploy Functions sia per
   il deploy Rules, e salta il seed sintetico; quindi disattivare la modalità
   clone e riattivare il seed sintetico nel processo operativo concordato;
4. verificare che Functions e rules staging accettino gli account sintetici e
   che nessun dato personale PRD sia usato nel QA ordinario.

Non copiare dati reali in staging per il rilascio ordinario. Per provare le
migrazioni batch usare il replay dell'export PRD nell'emulatore, come descritto
nel [runbook migrazione V2, sezione 21](../migrations/course-model-v2/RUNBOOK.md#21-prova-su-replay-dellexport-nellemulatore).

### Inventario Functions osservato

Il controllo live del 27/10/2026 ha riportato 22 Functions in staging e 7 in
PRD. Staging:

```text
assignSubscription, certificateEmailsDaily, checkEmailAvailability, courseIcs,
createManagedUser, deleteCourse, ensureOneSignalUser, grantSignupTrial,
joinWaitlist, leaveWaitlist, migrateLegacyUser, previewLegacyUserMigration,
recountCourseSubscribed, removeOneSignalEmail, revokeSubscription,
sendOneSignalNotification, sendTestCertificateEmail, setAttendance,
setManagedUserEmail, subscribeToCourse, unsubscribeFromCourse, updateSubscription
```

PRD:

```text
ensureOneSignalUser, notifyDemoLessonBooked, removeOneSignalEmail,
sendCertificateExpiryEmails, sendOneSignalNotification,
sendTestCertificateEmail, sendTestDemoLessonWebhook
```

## Decisioni go/no-go prima della finestra

Da prendere e registrare **prima** di fissare la finestra di rilascio.

### 1. Email certificati

La logica delle email certificati è già migrata nelle Functions
(`runCertificateEmails`, eseguita da `certificateEmailsDaily`), ma
`certificateFunctionsEnabled()` in `functions/src/index.ts` la esclude dalla
discovery in produzione (PR #8: "non devono esistere in produzione finché la
feature non viene promossa"). In PRD gira oggi la vecchia
`sendCertificateExpiryEmails` deployata da `main`, ogni giorno alle 09:00.

Il deploy Functions di `develop` proporrà di **cancellare**
`sendCertificateExpiryEmails`: se si accetta senza altro, le email certificati
in produzione **si fermano**. Scegliere una delle opzioni:

| Opzione | Cosa comporta |
|---|---|
| **A. Promuovere (consigliata)** | PR separata su `develop` che abilita `certificateEmailsDaily` anche in PRD (lasciando `sendTestCertificateEmail` solo staging/emulatore), verificata su staging. Nel deploy PRD accettare la cancellazione di `sendCertificateExpiryEmails`. |
| B. Mantenere la vecchia | Rifiutare la cancellazione al prompt della CLI: continua a girare il codice di `main`, che non viene più aggiornato. Va riconciliata al rilascio successivo. |
| C. Fermarle | Accettare la cancellazione e avvisare lo staff che i promemoria certificato non partono più. |

**Mai A e B insieme**: le due function girerebbero entrambe (08:00 e 09:00) e
ogni socio riceverebbe due email.

### 2. Migrazione V2 nella stessa finestra

La web nuova e le rules si pubblicano **dopo** apply e verify della migrazione,
nella stessa finestra (RUNBOOK §16). Servono: un responsabile dell'operazione,
un secondo operatore per la revisione di manifest e CSV, una finestra di
manutenzione concordata con lo staff e la possibilità di sospendere
registrazioni e operazioni gestionali. Senza queste condizioni il rilascio si
ferma dopo il deploy Functions (stato sicuro: le Functions sono tolleranti
V1/V2 e la web PRD attuale non le invoca).

### 3. WhatsApp demo

Lasciare `WHATSAPP_DEMO_MODE=test` in `functions/.env.fit-rope-app-1f575`.
Passare a `live` è una PR separata, solo dopo scenario Make e template Meta
approvati: `live` abilita la conferma all'iscrizione e il cron delle 19:00, che
manda WhatsApp reali e a pagamento.

## Prerequisiti PRD

### Versione e gate

- [ ] `develop` integrato in `main` con PR; `version-bump.yml` crea il commit
      `chore: bump version` su `main`. **Rilasciare dal commit di bump**: il
      merge commit ha ancora la versione vecchia in `version.json`, e il
      controllo di aggiornamento della PWA in `web/index.html` si basa su quel file.
- [ ] Verificare che quel commit sia equivalente a quello verificato su staging
      (`git diff <sha-staging> <sha-bump>` deve mostrare solo `pubspec.yaml`).
- [ ] CI verde: test Flutter, analyze, format, build web, test unitari Functions
      e test d'integrazione Emulator. `release.yml` valida soltanto, non pubblica.
- [ ] Ultimo deploy staging verde, smoke test compreso; QA manuale su staging
      di login, iscrizione/disiscrizione, waitlist, abbonamenti, presenze,
      regolamento.
- [ ] Punto clone staging risolto (sezione sopra).
- [ ] Decisioni go/no-go registrate.

### Backup Firestore

Le function di backup vengono create dal primo deploy PRD di `develop` e
falliscono se l'infrastruttura non esiste. Seguire
[Backup e ripristino Firestore](FIRESTORE_BACKUP_RESTORE.md):

- [ ] bucket `gs://fit-rope-app-1f575-firestore-backups` creato (EU, Standard,
      UBLA, Public Access Prevention), canary upload/download/delete riuscito,
      retention 30 giorni, soft delete 7 giorni, lifecycle 90 giorni;
- [ ] service account `fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com`
      con `roles/datastore.importExportAdmin` sul progetto e `roles/storage.admin`
      sul solo bucket; Firestore service agent con accesso al bucket;
- [ ] il deployer ha `roles/iam.serviceAccountUser` sul service account runtime;
- [ ] API Cloud Scheduler abilitata (in PRD già usata da
      `sendCertificateExpiryEmails`; ricontrollare).

Il backup Firestore non comprende Firebase Auth, rules o indici.

### Rules live da salvare

`firestore.rules` non esiste su `main`: le rules attive in PRD non sono nel
repository e senza una copia il rollback delle rules è impossibile.

- [ ] Salvare il testo delle rules live in una posizione privata (non nel
      repository), dalla console Firebase → Firestore → Regole (la cronologia
      mostra le versioni pubblicate) oppure via API:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://firebaserules.googleapis.com/v1/projects/fit-rope-app-1f575/releases/cloud.firestore"
# rulesetName dalla risposta, poi:
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://firebaserules.googleapis.com/v1/<rulesetName>"
```

- [ ] Annotare il `rulesetName` attivo: è il punto di ritorno del rollback.

### Configurazione servizi

- [ ] Secret Manager PRD: `ONESIGNAL_REST_API_KEY` presente; con
      `WHATSAPP_DEMO_MODE=test` anche `MAKE_WEBHOOK_URL` e `MAKE_WEBHOOK_KEY`
      (creati il 04/09/2026). Controllare solo l'esistenza, mai leggere o
      riportare i valori. Per crearli o ruotarli:
      `firebase functions:secrets:set <NOME> --project prod`, valore solo al
      prompt del CLI, poi ridistribuire le Functions.
- [ ] `functions/.env.fit-rope-app-1f575` contiene solo `WHATSAPP_DEMO_MODE`.
      **Non aggiungere `APP_ENV`**: con `APP_ENV=staging` le function di backup
      sparirebbero e quelle certificati/staging comparirebbero in PRD.
- [ ] Nessuna variabile `STAGING_*`, allowlist staging o `STAGING_CLONE_MODE` in
      PRD. La build web PRD usa `DefaultFirebaseOptions` del repository, senza
      `--dart-define` Firebase.
- [ ] `ONESIGNAL_APP_ID` non è un secret: il backend lo legge da configurazione
      con fallback al valore corrente; l'app web lo ha hardcoded in
      `lib/main.dart` (è quello di produzione).
- [ ] OneSignal dashboard, app di produzione: site URL `https://app.fithousemonza.it`
      e path del service worker coerente con `web/push/onesignal/OneSignalSDKWorker.js`.
- [ ] Firebase Auth PRD: `app.fithousemonza.it` tra i domini autorizzati;
      template email (reset password) invariati.
- [ ] Indici: nessuno richiesto dal codice attuale (le query WhatsApp/certificati
      usano un solo filtro). Se il rilascio ne introduce, crearli e attendere lo
      stato pronto prima dello smoke test.

### Riconciliazione Functions

Acquisire e revisionare l'inventario attuale:

```bash
firebase functions:list --project prod --json
firebase functions:list --project staging --json
```

Function attese in PRD dopo il deploy:

```text
subscribeToCourse, unsubscribeFromCourse, joinWaitlist, leaveWaitlist,
assignSubscription, updateSubscription, revokeSubscription,
createManagedUser, checkEmailAvailability, setManagedUserEmail,
grantSignupTrial, deleteCourse, recountCourseSubscribed, setAttendance,
previewLegacyUserMigration, migrateLegacyUser, sendOneSignalNotification,
ensureOneSignalUser, removeOneSignalEmail, courseIcs,
firestoreBackupDaily, firestoreBackupDailyCheck, sendTestDemoLessonWebhook
```

più `certificateEmailsDaily` solo con l'opzione A. Devono restare assenti
`sendTestCertificateEmail` e, finché la modalità non è `live`,
`sendDemoLessonWhatsappReminders`.

Destino delle function presenti oggi in PRD ma assenti dal codice di `develop`:

| Function | Origine | Azione al prompt di cancellazione |
|---|---|---|
| `notifyDemoLessonBooked` | branch WhatsApp mai integrato, deployata a mano | Cancellare: nessun client la invoca, la conferma ora è dentro `subscribeToCourse` |
| `sendTestCertificateEmail` | `main` | Cancellare: su `develop` è solo staging/emulatore |
| `sendCertificateExpiryEmails` | `main` | Secondo la decisione go/no-go 1 |
| `sendTestDemoLessonWebhook` | branch WhatsApp | Non è da cancellare: esiste anche su `develop` con `WHATSAPP_DEMO_MODE=test` e il deploy la aggiorna |

Il deploy PRD si fa **interattivo e senza `--force`**: in modalità non
interattiva la CLI si ferma davanti a qualunque function presente nel progetto
e assente dal sorgente; con `--force` cancellerebbe tutto senza chiedere.

## Sequenza di rilascio PRD

### Fase 0 — Comunicazione

- [ ] Comunicare allo staff data, durata e impatto della finestra: app in
      manutenzione, registrazioni e operazioni gestionali sospese, chiusura
      delle schede e delle PWA aperte prima della riapertura.

### Fase 1 — Backup e registro

- [ ] Creare un export Firestore di sicurezza manuale e verificarne il
      completamento ([runbook backup](FIRESTORE_BACKUP_RESTORE.md)).
- [ ] Registrare commit, project ID, operatore, timestamp, operation ID e URI
      del backup; nessun segreto o dato personale nel registro.
- [ ] Rules live salvate (prerequisito sopra).

### Fase 2 — Deploy Cloud Functions

Dal commit di bump, con il target esplicito `prod`:

```bash
cd functions
npm ci
npm run build
cd ..
firebase deploy --project prod --only functions
```

- [ ] Rispondere al prompt di cancellazione secondo la tabella di
      riconciliazione; non confermare cancellazioni non comprese.
- [ ] `firebase functions:list --project prod --json`: inventario atteso,
      region `europe-west8`, runtime `nodejs22`, secret binding.
- [ ] Cloud Scheduler: job di backup presenti; nessun job WhatsApp; job
      certificati secondo la decisione presa.
- [ ] Lanciare a mano il job `firestoreBackupDaily` (o attendere le 02:00 UTC)
      e verificare run `SUCCEEDED` e manifest in `_manifests/`.

Da qui la web PRD attuale continua a funzionare: non usa le callable nuove. Se
la finestra non è confermata, il rilascio può fermarsi qui.

### Fase 3 — Preparazione migrazione (prima della finestra)

Comandi e criteri nel [RUNBOOK migrazione](../migrations/course-model-v2/RUNBOOK.md),
sezioni 5–9 e 16.2–16.3.

- [ ] Ricontrollare i blocker futuri (il dry-run del 16/09 aveva un
      `SUBSCRIBED_COUNT_MISMATCH`): export di sicurezza prima di un
      `recountCourseSubscribed`, poi nuovo export dello stato da migrare.
- [ ] Replay di quell'export nell'emulatore (RUNBOOK §21): dry-run, apply corsi,
      apply utenti, verify, apply idempotente. **Ogni `--apply` passa da una
      guardia che verifica `FIRESTORE_EMULATOR_HOST`**: senza, il runner scrive
      in produzione.
- [ ] Dry-run PRD completo (`--dry-run --scope=all`), manifest e tre CSV
      revisionati da un secondo operatore, hash registrato. Report solo in
      `.context/migrations/`, mai in PR o issue.
- [ ] Il manifest è **deperibile** (`FUTURE_START` dipende dall'istante del
      dry-run e non produce `SOURCE_DRIFT`): se supera un giorno o i dati
      cambiano, rifare dry-run e revisione nella finestra.

### Fase 4 — Apertura finestra di manutenzione

- [ ] Pagina di manutenzione per i nuovi accessi web su Hostinger.
- [ ] Freeze operativo: niente registrazioni, creazione/modifica corsi e utenti,
      assegnazioni; schede di staff e operatori chiuse. Il freeze non blocca
      tecnicamente le scritture: se non si può garantire, fermarsi.
- [ ] Ripetere i controlli di RUNBOOK §10: Functions V1/V2 pubblicate, rules
      strette non ancora pubblicate, export completo, hash del manifest.

### Fase 5 — Migrazione dati

Seguire RUNBOOK §11–15 e §16.5–16.7:

- [ ] apply `courses`, poi apply `users` dal manifest approvato; `SOURCE_DRIFT`
      e `TARGET_CONFLICT` impongono lo stop anche con exit code 0;
- [ ] `node scripts/reconcile_subscription_model_version.js --project=fit-rope-app-1f575`,
      revisione `safe`/`manual`, apply dei soli `safe` con
      `--apply --confirm-project=fit-rope-app-1f575`;
- [ ] `--verify --scope=all`: leggere `failures: 0` nel JSON. L'exit code 2 può
      dipendere da `enrollmentBlockers` preesistenti: ognuno va spiegato prima
      di proseguire;
- [ ] ripetere l'apply con lo stesso manifest: zero scritture
      (`ALREADY_APPLIED`/`SKIPPED`).

Esito non chiaro → fermarsi con la manutenzione attiva e seguire RUNBOOK §17.
Non pubblicare web e rules.

### Fase 6 — Web e rules, nella stessa finestra

Web nuova con rules vecchie non registra utenti; web vecchia con rules nuove
fallisce su registrazione e creazione utenti. Le due pubblicazioni vanno una
dietro l'altra, a manutenzione ancora attiva.

```bash
flutter pub get
flutter build web --wasm --release
python3 tool/precompress_web.py build/web
```

- [ ] Build senza `--dart-define` (default `APP_ENV=prod`, Firebase PRD) e
      senza `tool/apply_test_branding.py`. Controllare `build/web/version.json`
      (versione del commit di bump) e la presenza di `build/web/.htaccess`.
- [ ] Il comando di build è lo stesso della CI (`ci.yml`, `release.yml`) del
      commit rilasciato.
- [ ] Prima del primo upload con `.htaccess` nuova: prova Apache locale
      (`tool/hostinger/local_apache_test.sh`); una `.htaccess` rotta dà 500 su
      tutto il sito. Conservare una copia della build e della `.htaccess`
      attualmente online per il rollback.
- [ ] Upload di `build/web` su Hostinger, sostituendo la pagina di manutenzione.
- [ ] **Subito dopo**: diff di `firestore.rules` contro le rules approvate e
      `firebase deploy --project prod --only firestore:rules`.

Perché qui l'ordine dei rollout invertiti non si applica: il gate regolamento
(web → functions → rules) e le presenze (functions → rules → web) descritti in
[`README_ISCRIZIONI.md`](../../lib/api/courses/README_ISCRIZIONI.md) presuppongono
una web PRD che chiama già le callable. La web di `main` non le chiama, quindi
il passaggio avviene tutto nella finestra, a schede chiuse.

### Fase 7 — Verifiche e smoke test

- [ ] Rieseguire `--verify --scope=all` (RUNBOOK §16.9).
- [ ] `curl -s https://app.fithousemonza.it/version.json` restituisce la nuova versione.
- [ ] `curl -sI https://app.fithousemonza.it/main.dart.js`: `Cache-Control`
      `max-age=1800` (non i 7 giorni di default di LiteSpeed).
- [ ] `tool/hostinger/verify_brotli.sh https://app.fithousemonza.it main.dart.js`
      → `ESITO: OK`.
- [ ] Da una sessione fresca, con account e corsi concordati con il responsabile
      operativo e senza toccare utenti reali:
  - [ ] login e logout; registrazione con indirizzo di test autorizzato;
  - [ ] creazione utente Admin e modifica email (`checkEmailAvailability`,
        `createManagedUser`, `setManagedUserEmail`);
  - [ ] regolamento: dialog alla prima iscrizione;
  - [ ] iscrizione, disiscrizione e rimborso nei piani Prova, Pacchetto e
        Frequenza; waitlist e contatori;
  - [ ] assegnazione, modifica e revoca abbonamento;
  - [ ] check-in e appello presenze;
  - [ ] link `.ics` (`courseIcs`) dalla mail di conferma prova;
  - [ ] email di conferma prova ricevuta (OneSignal);
  - [ ] WhatsApp: solo la callable di prova, verso un numero approvato.
- [ ] Log delle callable senza errori inattesi; una scrittura client diretta su
      un campo server-owned viene rifiutata dalle rules.

### Fase 8 — Chiusura finestra

- [ ] Bonifica degli utenti attivi esclusi dalla migrazione dalla card Admin di
      `UserDetailPage` (RUNBOOK §16.10): nessun utente corrente senza
      abbonamento valido o esclusione approvata.
- [ ] Rimuovere il freeze, comunicare la riapertura e chiedere a staff e soci di
      ricaricare l'app (le PWA aperte prima della finestra possono restare
      sulla versione vecchia fino al ricaricamento).
- [ ] Il giorno dopo: run di backup `SUCCEEDED` e manifest presente; email
      certificati partite secondo la decisione presa; nessun job WhatsApp eseguito.

## Rollback

- **Prima della fase 6**: nulla da ripristinare lato client; le Functions sono
  tolleranti V1/V2. Fermarsi, mantenere il freeze, seguire RUNBOOK §17 per i dati.
- **Web**: ripubblicare su Hostinger la build e la `.htaccess` conservate;
  verificare cache e Brotli.
- **Rules**: ripubblicare il ruleset salvato nei prerequisiti (console →
  cronologia Regole, oppure `firebase deploy --only firestore:rules` dal testo
  salvato). Rules vecchie con web nuova non registrano utenti: web e rules si
  riportano indietro insieme.
- **Functions**: ridistribuire il commit precedente con
  `firebase deploy --project prod --only functions`. Le function cancellate nel
  deploy (es. `sendCertificateExpiryEmails`) non tornano da sole: vanno
  ridistribuite da `main`.
- **Dati**: non si ripristinano con il rollback applicativo. Fermare le
  scritture, acquisire un export dello stato attuale e seguire il
  [ripristino Firestore](FIRESTORE_BACKUP_RESTORE.md), verificando prima su un
  database temporaneo. Un import su `(default)` sovrascrive i documenti omonimi
  e non cancella quelli extra: richiede approvazione e procedura dedicata.

## Criteri di chiusura

- [ ] Inventario Functions PRD uguale all'atteso; nessuna function staging-only
      o schedulazione non approvata.
- [ ] Email certificati gestite secondo la decisione (mai doppie).
- [ ] Migrazione applicata, verify con `failures: 0`, apply idempotente, esclusi
      bonificati o approvati.
- [ ] Web PRD online con la nuova versione, progetto Firebase corretto, cache e
      Brotli verificati.
- [ ] Rules pubblicate subito dopo la web; ruleset precedente salvato.
- [ ] Backup PRD automatico verificato.
- [ ] Registro del rilascio completo (commit, esiti, operatori, timestamp,
      follow-up), senza segreti né dati personali nei documenti versionati.
