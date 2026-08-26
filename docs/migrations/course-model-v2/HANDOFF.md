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
  `.context/migrations/prod-2026-08-26-2010-dry-run`. Staging ha una sola
  `WARNING`; PRD ha 5 `BLOCKER` di integrità da risolvere prima di qualunque
  apply.

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
