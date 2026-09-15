# Handoff operativo — migrazione Course Model V2 e backup Firestore

Aggiornato il 26 agosto 2026 (ripresa handoff). Questo documento permette a un nuovo agente o
operatore di riprendere il lavoro senza ricostruire le decisioni dalla cronologia
della conversazione.

## 1. Stato del repository

- Workspace: `/Users/Frank/conductor/workspaces/fitrope_app/bucharest`.
- Branch: `fgrotta/corsi-tipi-tag-iscrizioni`; non rinominarlo.
- Target: `origin/develop`.
- PR aperta: [#12 — migrazione tipo/tag corsi e abbonamenti legacy](https://github.com/fgrotta/fitrope_app/pull/12).
- Ultimo commit della documentazione: `63975bd docs: add course model migration runbook`.
- Ultimo commit funzionale: `de0d6b5 feat: migrate course types and legacy subscriptions`.
- I check della PR sono verdi sul commit pubblicato, ma **non** includono il
  lavoro non committato elencato sotto.

Fonti di verità da leggere prima di intervenire:

1. [PIANO.md](PIANO.md): baseline, matrici, CSV e vincoli di modello.
2. [RUNBOOK.md](RUNBOOK.md): uso dettagliato del runner.
3. [Backup e ripristino Firestore](../../operations/FIRESTORE_BACKUP_RESTORE.md):
   bucket, export, download e restore.
4. `scripts/backfillCourseModel.js`: comportamento realmente eseguibile.

Non copiare in Git manifest, export o CSV operativi: possono contenere PII e
devono restare sotto `.context/migrations/` o in
`/Users/Frank/Backups/FitRope/` con permessi privati.

## 2. Decisioni già approvate

### Bucket e retention

| Ambiente | Bucket | Location |
|---|---|---|
| Staging | `gs://fit-rope-staging-firestore-backups` | `europe-west8` |
| PRD | `gs://fit-rope-app-1f575-firestore-backups` | `EU` (vicino a Firestore `eur3`) |

Entrambi devono usare Storage Standard, Uniform Bucket-Level Access, Public
Access Prevention, retention minima 30 giorni, lifecycle delete a 90 giorni e
soft delete a 7 giorni. Eseguire prima un canary esportazione/ripristino; non
bloccare irreversibilmente la retention nel rollout iniziale.

### Backup automatico PRD

- Export completo del database `(default)` ogni notte alle `02:00 UTC`.
- Prefisso:
  `automatic/YYYY/MM/DD/firestore-<timestamp>-attempt-N`.
- Manifest di successo: `_manifests/YYYY-MM-DD.json`.
- Check alle `03:00 UTC` che fallisce se il run non è `SUCCEEDED`.
- Funzioni assenti da staging ed Emulator e guardia runtime sul project ID
  `fit-rope-app-1f575`.
- Service account dedicato:
  `fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com`.
- Ruoli minimi: `roles/datastore.importExportAdmin` sul progetto e
  `roles/storage.admin` sul solo bucket; concedere anche al Firestore service
  agent l'accesso al bucket e al deployer `iam.serviceAccounts.actAs`.
- Non usare i backup schedulati nativi Firestore: non consentono né l'orario
  esatto né il bucket richiesto. L'implementazione scelta usa
  `FirestoreAdminClient.exportDocuments` e Cloud Scheduler.

### Rehearsal migrazione

- Creare e scaricare prima il backup dello staging.
- Creare un solo export formale PRD, scaricarlo e copiare quella stessa versione
  nel bucket staging per il rehearsal.
- La copia PRD deve sostituire temporaneamente Firestore staging `(default)`;
  Firebase Auth non viene copiato né cancellato.
- Prima di importare PRD in staging:
  - sospendere il workflow di deploy staging;
  - mettere in pausa
    `firebase-schedule-certificateEmailsDaily-europe-west8`;
  - applicare rules temporanee deny-by-default;
  - creare un Admin Auth casuale ed effimero, unico soggetto autorizzato.
- Un import non elimina i documenti assenti dall'export: svuotare staging prima
  dell'import PRD e di nuovo prima del ripristino dello staging originale.
- Nel clone eseguire dry-run, una migrazione Admin automatica, una guidata,
  apply batch, verify, seconda apply idempotente e audit delle iscrizioni.
- Al termine ripristinare il backup originale staging, rules, scheduler,
  workflow e Auth, eliminando l'Admin effimero.
- Dopo il rehearsal eseguire in PRD soltanto il dry-run. Nessun apply PRD è
  autorizzato in questa fase; per l'apply servirà un nuovo backup pre-operazione.

### Iscrizioni passate e future

- Il runner migra tutti i documenti corso convertibili, passati e futuri.
- Non deve riscrivere `users.courses`, `waitlistCourses`,
  `cancelledEnrollments` o `enrollmentConsumption`: gli ID dei corsi restano
  invariati e inventare consumo storico rischierebbe di creare o bruciare
  crediti.
- Aggiungere `enrollment-integrity-report.csv`:
  - booking futuro senza corso o waitlist futura incoerente: blocker;
  - anomalia esclusivamente storica: warning;
  - gli array e registri sopra devono essere byte-identici prima/dopo.
- Le subscription scadute vengono create ma escluse dallo snapshot attivo.
- Gli utenti con subscription nominalmente futura restano esclusi dal batch e
  passano dalla migrazione guidata Admin.

### Migrazione singolo utente

Interfacce approvate:

```text
previewLegacyUserMigration({ userId })

migrateLegacyUser({
  userId,
  mode: AUTO | GUIDED,
  expectedFingerprint,
  target?
})
```

Stati pubblici: `MIGRATED`, `AUTO_CONVERTIBLE`, `MANUAL_REQUIRED`, `CONFLICT`,
`NOT_APPLICABLE`.

- Solo Admin, con autorizzazione verificata server-side.
- `AUTO` riusa il trasformatore batch.
- `GUIDED` offre tutto il catalogo corrente Open/PT; richiede piano, inizio e
  fine coerenti in Europe/Rome e, per ENTRIES, credito residuo tra zero e il
  massimo del piano.
- La transazione rilegge sorgente e target e confronta il fingerprint.
- Batch e callable scrivono la stessa marca server-owned
  `legacySubscriptionMigration` con versione, origine, subscription, timestamp
  e attore.
- La card in `UserDetailPage` è Admin-only, visibile soltanto su desktop e
  soltanto per utenti non migrati. `CONFLICT` è read-only; dopo il successo la
  cache viene invalidata e la card scompare.

## 3. Lavoro presente ma non committato

Il worktree contiene modifiche da preservare e revisionare:

- `functions/src/firestoreBackup.ts`: prima implementazione dell'export
  schedulato e del check delle 03:00.
- `functions/src/__tests__/firestoreBackup.test.ts`: tre test unitari iniziali.
- `functions/src/index.ts`: export delle due scheduled functions e delle due
  callable di migrazione utente.
- `functions/src/migration/userHandler.ts`: preview e migrazione AUTO/GUIDED.
- `functions/src/migration/marker.ts`: schema unico del marker batch/Admin.
- `lib/api/subscriptions/legacy_user_migration.dart`: facade callable Flutter.
- `lib/components/legacy_user_migration_card.dart` e `UserDetailPage`: card
  Admin desktop con flusso automatico/guidato.
- `functions/package.json` e lockfile: dipendenza diretta
  `@google-cloud/firestore`.
- `firestore.rules`: blocco client su `_systemBackupRuns` e
  `legacySubscriptionMigration`.
- `docs/operations/FIRESTORE_BACKUP_RESTORE.md` e collegamenti dai README.
- `functions/src/__tests__/indexExports.test.ts`: gate PRD/staging/emulatore.
- `scripts/backfillCourseModel.js`: marker condiviso, fingerprint degli array
  iscrizioni e `enrollment-integrity-report.csv`.

`firepit-log.txt` è un artefatto locale non correlato: non includerlo nel
commit. Prima di modificare qualunque file, rieseguire `git status --short` e
non scartare il worktree.

Verifica locale già eseguita sul worktree corrente:

```text
cd functions && npm run build && npm test -- --runInBand --detectOpenHandles
18 suite passate, 330 test passati

PATH="/usr/local/opt/openjdk@21/bin:$PATH" npm run test:integration
3 suite passate, 40 test passati

flutter test
352 test passati
```

La ripresa ha eliminato l'open handle e completato i test mirati con
`--detectOpenHandles`.

## 4. Gap e rischi da risolvere prima del commit

### Backup — validazione reale iniziale completata

- Ora usa `event.scheduleTime`, lease transazionale, riconciliazione degli
  `STARTING` orfani e timer sempre cancellato.
- Verificare sul client reale il recupero LRO tramite
  `checkExportDocumentsProgress`; la sola compilazione TypeScript non prova il
  comportamento runtime.
- I test coprono progetto errato, errore API, resume RUNNING, STARTING orfano,
  retry FAILED, manifest fallito, concorrenza e `scheduleTime`.
- Il lifecycle JSON e i comandi IAM/canary sono ora versionati nel runbook.
- Il 26 agosto 2026 sono stati creati e verificati entrambi i bucket con canary,
  retention 30 giorni, soft delete 7 giorni e lifecycle delete a 90 giorni.
- Gli export completi PRD e staging con run ID
  `first-verification-2026-08-26-1955` sono terminati con successo e sono stati
  scaricati sotto `/Users/Frank/Backups/FitRope/firestore/` con checksum e
  permessi privati.
- Non sono ancora stati eseguiti il deploy delle scheduled Functions, l'IAM del
  service account runtime dedicato, il drill di ripristino o il rehearsal con
  clone PRD su staging.

### Migrazione singolo utente — implementata, integrazione da eseguire

- Preview `CONFLICT`, classificazione ruoli, validazione GUIDED, marker condiviso
  batch/callable, card desktop e smoke test staging sono implementati.
- I test unitari, widget ed Emulator sono verdi; la doppia richiesta concorrente
  crea una sola subscription e preserva gli array storici.

### Migrazione e report — implementata e verificata su Emulator

- `enrollment-integrity-report.csv` è generato e `--verify` blocca sulle
  incoerenze future. Il manifest protegge con fingerprint gli array/registri di
  iscrizione e l'apply rifiuta ogni drift.
- Le 71 bonifiche manuali e i gate finali devono restare documentati; non
  rimuovere il ramo legacy finché non sono risolte o approvate come eccezioni.
- I dry-run reali read-only del 26 agosto 2026 sono in
  `.context/migrations/staging-2026-08-26-2002-dry-run` e
  `.context/migrations/prod-2026-08-26-2010-dry-run`. I `BLOCKER` di integrità
  PRD erano 5 a quella data; il conteggio dipende dall'istante di esecuzione e
  non dalla qualità dei dati (vedi sezione 7). Nessun apply è autorizzato finché
  non sono risolti o approvati come eccezioni.
- La simulazione completa della migrazione (dry-run, apply, verify, apply
  idempotente) è stata eseguita con esito positivo su un replay dell'export PRD
  nell'emulatore: dettagli, comandi e rischi emersi nella sezione 7.

## 5. Ordine raccomandato di ripresa

1. Correggere idempotenza, `scheduleTime`, riconciliazione LRO e timer del
   backup; completare unit test e documentazione dei comandi.
2. Correggere preview/classificazione della migrazione singola, condividere la
   marca col batch e aggiungere test unitari/Emulator.
3. Implementare card Admin desktop e relativi widget test.
4. Implementare l'audit delle iscrizioni passate/future nel runner.
5. Eseguire:

   ```bash
   cd functions
   npm run build
   npm test -- --runInBand --detectOpenHandles
   npm run test:integration
   cd ..
   flutter test
   flutter analyze --no-fatal-infos
   dart format --output=none --set-exit-if-changed .
   ```

   La suite Emulator richiede Java 21+.

6. Revisionare `git diff origin/develop...` e separare il commit applicativo da
   artefatti locali/PII. Aggiornare e pushare la PR #12 verso `develop`.
7. Solo dopo CI verde: creare bucket e IAM, fare canary export/restore, attivare
   il backup PRD, forzare un run e verificare manifest e restore temporaneo.
8. Creare/scaricare backup staging e PRD, quindi svolgere il rehearsal protetto
   e ripristinare staging.
9. Produrre il dry-run PRD finale e consegnare i report per approvazione, senza
   apply.

## 6. Criteri di chiusura

- Tutte le suite locali e CI passano senza open handle.
- Le scheduled function esistono solo in PRD; il run delle 02:00 termina
  `SUCCEEDED` e il check delle 03:00 passa.
- Almeno un export PRD è stato importato e validato in un database temporaneo.
- Backup staging e PRD sono scaricati sotto `/Users/Frank/Backups/FitRope/` con
  checksum e permessi privati.
- Migrazione Admin automatica e guidata funzionano soltanto su desktop e solo
  per utenti non migrati.
- Report iscrizioni senza blocker sui corsi futuri e array storici invariati.
- Staging è stato ripristinato allo stato originale e tutti i blocchi temporanei
  sono stati rimossi.
- PRD dispone soltanto di dry-run approvato; nessuna migrazione reale viene
  applicata senza una successiva finestra autorizzata.

## 7. Aggiornamento 8 settembre 2026 — replay su emulatore e simulazione completa

### Metodo: replay dell'export PRD sull'emulatore

L'emulatore Firestore importa **direttamente** un export prodotto da
`gcloud firestore export`, non solo gli export nativi di `emulators:export`. Va
puntato alla directory che contiene `<run-id>.overall_export_metadata`:

```bash
PATH="/usr/local/opt/openjdk@21/bin:$PATH" firebase emulators:start \
  --project fit-rope-app-1f575 --only firestore \
  --import=/Users/Frank/Backups/FitRope/firestore/prod/<data>/<run-id>/<run-id>
```

`scripts/backfillCourseModel.js` non ha guardie sul project ID e usa
`admin.initializeApp({ projectId })`, quindi rispetta `FIRESTORE_EMULATOR_HOST`
e gira contro l'emulatore senza alcuna modifica.

Questo sostituisce il clone PRD dentro Firestore staging **per tutta la parte
batch**. I dati restano sulla macchina dove il backup è già scaricato, non serve
svuotare staging né sospendere workflow, scheduler e rules, e il ripristino
consiste nello spegnere il processo. Il clone su staging resta necessario solo
per ciò che l'emulatore non copre: le callable della migrazione guidata e la UI
Admin.

**Guardia obbligatoria.** Un `--apply` senza `FIRESTORE_EMULATOR_HOST` scrive in
**produzione**. Usare un wrapper che rifiuti di eseguire il runner se
l'emulatore non risponde e se non contiene lo snapshot atteso; copia di lavoro
in `.context/sim/guard.sh`.

### Simulazione completa eseguita — esito positivo

Eseguita sull'export `first-verification-2026-08-26-1955` (21/21 checksum
verificati) replicato nell'emulatore.

| Passo | Comando | Esito |
|---|---|---|
| 1 | `--dry-run --scope=all` | 1965 corsi `CONVERTIBLE`, 11 `IGNORED`; 74 utenti `CONVERTIBLE`, 432 `IGNORED` |
| 2 | `--apply --scope=courses` | 1965 `APPLIED`, 11 `SKIPPED`; nessun drift, nessun conflitto |
| 3 | `--apply --scope=users` | 74 `APPLIED`, 432 `SKIPPED` |
| 4 | `--verify --scope=all` | `failures: 0`, `hyroxSubscriptions: 0`, `hyroxSnapshots: 0`; exit 2 solo per i `BLOCKER` di integrità preesistenti |
| 5 | `--apply` ripetuto | 2039 `ALREADY_APPLIED`, 443 `SKIPPED`, zero nuove scritture |

**Invarianti rispettate.** Confronto campo per campo prima/dopo su tutti i 506
utenti e 1976 corsi: zero modifiche a `courses`, `waitlistCourses`,
`cancelledEnrollments`, `enrollmentConsumption` lato utente e a `subscribed`,
`waitlist`, `capacity`, `startDate` lato corso.

**Prodotto dalla migrazione.** 74 subscription, tutte famiglia `OPEN` e modalità
`FREQUENCY`; 39 già scadute, conservate nella collezione ma **escluse** dallo
snapshot; 35 vive, presenti in `activeSubscriptions`; 74 marker
`legacySubscriptionMigration`; 1965 corsi con `courseModelV2: true`.

**Produzione verificata intatta** a simulazione conclusa: 0 subscription e 0
corsi V2 su PRD live.

Nota su `--verify`: con dati PRD termina con exit 2 anche dopo un apply perfetto,
perché il gate include `enrollmentBlockers > 0` e quei blocker sono anomalie
preesistenti dei dati, non fallimenti dell'apply. Il codice di uscita va sempre
letto insieme al JSON.

### Rischio nuovo: il manifest è deperibile e nessuno se ne accorge

`FUTURE_START` confronta la data iniziale nominale con `evaluatedAtMillis`
(`functions/src/migration/userTransform.ts:176`), e la severità dell'integrity
report confronta `startDate` del corso con lo stesso istante. Il fingerprint del
manifest copre i campi sorgente dell'utente e gli array di iscrizione, **non
l'istante di valutazione**.

Conseguenza misurata: lo stesso export, valutato a dodici giorni di distanza, ha
prodotto **74 utenti convertibili invece di 58**. I 16 utenti spostati erano
`FUTURE_START` con data iniziale nominale a inizio settembre, ormai passata.
Applicare un manifest vecchio non produce `SOURCE_DRIFT` — le decisioni
congelate vengono applicate così come sono — quindi la migrazione
**sotto-converte in silenzio**. Il verso è quello prudente, esclude invece di
includere, ma non viene segnalato da nessuna parte.

Regola operativa: manifest prodotto e applicato nella stessa finestra. Se fra
dry-run e apply passa più di un giorno, rifare il dry-run e riconfrontare gli
hash prima di procedere.

Lo stesso meccanismo governa i `BLOCKER` di integrità: i 5 del 26 agosto sono 2
all'8 settembre, perché tre dei corsi coinvolti sono diventati passati. Quel
numero misura la distanza fra i corsi anomali e la data di esecuzione, non la
qualità dei dati.

### Il backup del 26 agosto era arretrato — sostituito

PRD live all'8 settembre aveva 2015 corsi e 535 utenti, contro 1976 e 506
dell'export del 26 agosto. Quell'export vale come banco di prova del meccanismo,
non come base decisionale, ed è stato sostituito da un export nuovo lo stesso
giorno: vedi la sottosezione seguente, che riporta la baseline corrente.

### Rilievo staging chiarito

`SUBSCRIBED_COUNT_MISMATCH` su `stg_open_full` **non coinvolge alcun utente**: il
controllo è a livello di corso e passa `userId` nullo per costruzione
(`scripts/backfillCourseModel.js:373`). Il seed crea quel corso con
`subscribed: 1` e `waitlist: ["stg_member"]` senza che nessuno lo abbia in
`courses`, per avere un corso pieno su cui provare la waitlist: il contatore non
è mai corrisposto a una persona.

Non correggerlo con `recountCourseSubscribed`: porterebbe `subscribed` a zero, il
corso smetterebbe di essere pieno e la fixture della waitlist sarebbe distrutta.
Le strade praticabili sono accettarlo come artefatto noto del seed, oppure
modificare il seed perché iscriva un utente sintetico (per esempio
`stg_qa_nosub`) così che il contatore corrisponda a una persona reale.

### Nota sull'orologio dell'ambiente

Durante la sessione dell'8 settembre l'ambiente ha riportato prima l'8 settembre,
poi il 27 agosto, poi di nuovo l'8 settembre. Run ID, nomi delle directory dei
report e `evaluated_at` derivano da quell'orologio. Verificare `date -u` prima di
avviare un run operativo e non usare il nome della directory come prova della
data: la fonte attendibile è `evaluated_at` dentro i CSV e il manifest.

### Export del 8 settembre 2026 e seconda simulazione — baseline corrente

Export manuale `manual/sim-rerun-2026-09-08-1634` nel bucket PRD, operazione
terminata `SUCCESSFUL`, scaricato in
`/Users/Frank/Backups/FitRope/firestore/prod/2026-09-08/sim-rerun-2026-09-08-1634/`
con 21/21 checksum verificati e permessi privati. Corrisponde esattamente a PRD
live al momento dell'esecuzione: **2015 corsi, 535 utenti**.

Su questo export è stata rieseguita la sequenza completa, tramite
l'orchestratore `.context/sim/run-simulation.sh` (guardia incorporata, snapshot
degli invarianti, spegnimento automatico dell'emulatore).

| Passo | Esito |
|---|---|
| dry-run | 2003 corsi `CONVERTIBLE`, 12 `IGNORED`; 72 utenti `CONVERTIBLE`, 463 `IGNORED` |
| apply corsi | 2003 `APPLIED`, 12 `SKIPPED` |
| apply utenti | 72 `APPLIED`, 463 `SKIPPED` |
| verify | **exit 0**: `failures: 0`, zero residui HYROX, `enrollmentBlockers: 0` |
| apply ripetuto | 2075 `ALREADY_APPLIED`, 475 `SKIPPED`, zero nuove scritture |
| invarianti | zero documenti modificati su 535 utenti e 2015 corsi |

Prodotte 72 subscription, tutte `OPEN`/`FREQUENCY`: 35 scadute escluse dallo
snapshot, 37 vive incluse in `activeSubscriptions`, 72 marker
`legacySubscriptionMigration`, 2003 corsi con `courseModelV2: true`. Produzione
riverificata intatta a fine corsa: 0 subscription e 0 corsi V2.

**Zero BLOCKER di integrità, ma va letto con precisione.** Dei 5 blocker del 26
agosto, 3 (`SUBSCRIBED_COUNT_MISMATCH` sui corsi `MAhygAt5jFZ2UpAcHU0h`,
`VI3kDJB4fyrOLy7f723i`, `vh2Kz20KvQyK0Eccmng4`) sono **effettivamente rientrati**
in produzione: i contatori ora corrispondono ai riferimenti e quei corsi non
compaiono più nel report. I 2 `CANCELLED_COURSE_MISSING` sul corso
`jf7iwZ3cDODrD45u3PK9` **non sono stati risolti**: sono soltanto scaduti,
l'anomalia è ancora nei dati e ora compare come `WARNING` perché la data del
corso è passata. «Zero blocker» significa che nessuna anomalia riguarda più un
corso futuro, non che i dati siano stati bonificati. Restano 1537 `WARNING`:
1189 prenotazioni senza corso, 298 mismatch di contatore, 50 disiscrizioni
orfane.

**Composizione dei 29 utenti nuovi** rispetto al 26 agosto: +23
`TRIAL_NOT_SUPPORTED`, +8 `FUTURE_START`, +1 `INVALID_LEGACY_TYPE`, −1
`INVALID_TAG_SHAPE`, −2 `CONVERTIBLE`. I convertibili scendono da 74 a 72 pur
con 29 utenti in più: la crescita dell'utenza è quasi tutta di abbonamenti prova,
che il batch non converte per scelta.

**`FUTURE_START` è una coda strutturale, non un residuo da smaltire.** È passato
da 4 a 12 in tredici giorni. I dodici casi sono abbonamenti mensili,
trimestrali, semestrali e annuali con scadenze da ottobre 2026 ad aprile 2028:
sono rinnovi. Poiché la data iniziale nominale si ottiene sottraendo la durata
dalla scadenza, ogni rinnovo recente la colloca nel futuro e l'utente viene
escluso dal batch. Aspettare non svuota la coda, la sposta: va gestita dalla
migrazione guidata Admin e il suo peso cresce col ritmo dei rinnovi.

**Configurazione del bucket di backup verificata sul campo.** Tutti i requisiti
decisi risultano effettivamente in vigore su
`gs://fit-rope-app-1f575-firestore-backups`: location `EU`, Storage Standard,
uniform bucket-level access attivo, public access prevention `enforced`,
retention di 30 giorni non bloccata irreversibilmente, soft delete di 7 giorni,
lifecycle di cancellazione a 90 giorni.
