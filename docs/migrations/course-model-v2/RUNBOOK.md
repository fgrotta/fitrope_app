# Runbook operativo della migrazione

Questa procedura descrive come usare il runner
`scripts/backfillCourseModel.js` in modo ripetibile e verificabile. Leggere prima
il [piano completo](PIANO.md). Per Prova e Pacchetti leggere anche
[PROVA_E_PACCHETTI.md](PROVA_E_PACCHETTI.md).
L'ultimo riscontro aggregato di produzione è in
[DRY_RUN_PRD_2026-09-16.md](DRY_RUN_PRD_2026-09-16.md).

## 1. Cosa modifica il runner

Con `--apply`, il runner può effettuare due classi di scrittura:

- `courses`: aggiunge o normalizza `courseType`, `tag`, `tags` e
  `courseModelV2` tramite `BulkWriter`;
- `users` e `subscriptions`: crea una subscription OPEN o PT con ID deterministico e
  aggiorna `activeSubscriptions` e il marker server-owned
  `legacySubscriptionMigration` nella stessa transazione; imposta inoltre
  `subscriptionModelVersion: 2` e riallinea il registro consumi legacy.

Il runner non elimina i campi legacy dell'utente. I corsi e gli utenti esclusi
rimangono invariati e vengono elencati nei report.

Per i documenti utente il dry-run v2 espone, separatamente dalla decisione di
conversione V2, i default da normalizzare: ruolo `User` se assente, `null` o
vuoto; tag `Open` se assenti, `null` o `[]` e `tipologiaIscrizione` è un piano
legacy riconosciuto. Ruoli espliciti e tag non vuoti sono conservati, anche se
ambigui. Il ruolo viene assegnato anche senza piano legacy. `--verify` riporta
`normalizationPending`; deve essere zero dopo l'apply. L'apply accetta solo
manifest versione 2 e confronta il fingerprint della sorgente originale,
anche quando una precedente apply ha già salvato i default.

L'anteprima Admin mostra gli stessi default. `NORMALIZE` salva solo quei campi;
`AUTO` e `GUIDED` li salvano nella stessa transazione della subscription.
L'azione è disponibile anche per profili esclusi o già migrati. La scelta
guidata PT resta valida anche se il default legacy è `Open`.

Le tre modalità sono separate:

1. `--dry-run` legge Firestore e genera manifest e CSV senza scritture;
2. `--apply` applica esclusivamente le decisioni congelate in un manifest;
3. `--verify` esegue una nuova scansione read-only e segnala ciò che resta da
   migrare o è in conflitto.

## 2. Prerequisiti

Prima di operare su produzione verificare tutti questi punti:

- la versione contenente runner, trasformatori e Functions V1/V2 è stata
  revisionata e approvata;
- Node.js è compreso nell'intervallo dichiarato dal progetto (`>=22 <25`);
- le dipendenze di `functions/` sono installate;
- l'operatore dispone di Application Default Credentials per il progetto;
- è stato concordato un responsabile dell'operazione e un intervallo di freeze;
- è disponibile un export Firestore completato e verificato;
- nessuna regola Firestore stretta è stata ancora pubblicata prima della fase
  prevista dal rollout;
- i report possono restare localmente sotto `.context/migrations/` senza essere
  copiati in Git o sistemi di ticketing.

Java 21 non è richiesto dal runner, ma è richiesto per provare la suite completa
con Firebase Emulator.

## 3. Preparazione della postazione

Dalla root del repository:

```bash
git status --short
git rev-parse HEAD
node --version
java -version
```

Installare e compilare le Functions. La build è obbligatoria perché il runner
carica i trasformatori compilati da `functions/lib/migration/`.

```bash
cd functions
npm ci
npm run build
cd ..
```

Prima dell'accesso a produzione è consigliato rieseguire almeno:

```bash
cd functions
npm test
npm run test:integration
cd ..
```

La suite d'integrazione usa Firebase Emulator e verifica anche che dry-run,
apply idempotente, `SOURCE_DRIFT` e `TARGET_CONFLICT` funzionino come previsto.

## 4. Autenticazione e selezione del progetto

Il runner usa Firebase Admin SDK e le Application Default Credentials (ADC),
non la sessione interattiva di `firebase login`. Su una postazione operativa:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project fit-rope-app-1f575
gcloud auth application-default print-access-token
```

L'account deve avere accesso Firestore in lettura per `--dry-run`/`--verify` e
in scrittura per `--apply`. L'export richiede inoltre i permessi Firestore
import/export e accesso al bucket scelto.

Il progetto non viene ricavato implicitamente dalla configurazione locale:
`--project` è sempre obbligatorio. Per produzione usare esattamente:

```text
fit-rope-app-1f575
```

Non usare l'alias Firebase `prod` nel runner: il valore deve essere il project ID
reale. `--apply` richiede anche una seconda conferma identica tramite
`--confirm-project`.

## 5. Export di sicurezza

Prima del dry-run definitivo creare un export Firestore in un bucket controllato
e registrare percorso, data, operatore e stato di completamento. Esempio, dopo
aver sostituito il percorso del bucket:

```bash
gcloud firestore export gs://BUCKET_CONTROLLATO/fitrope/course-model-v2/AAAA-MM-GG \
  --project=fit-rope-app-1f575
```

Non proseguire se l'export fallisce o non è visibile nella console Firestore.
Non salvare export o credenziali nel repository.

## 6. Scegliere un run ID

Usare un nome leggibile e univoco, ad esempio:

```text
prod-2026-08-26-1800-dry-run
```

Ogni `--report-dir` deve essere interno a `.context/migrations/`. Il runner
rifiuta intenzionalmente directory diverse per evitare la pubblicazione
accidentale di dati personali.

Se `--report-dir` viene omesso, il runner crea una directory con timestamp. In
produzione è preferibile specificarlo per rendere immediata la tracciabilità.

## 7. Eseguire il dry-run completo

Il comando raccomandato usa lo script npm, che ricompila TypeScript prima di
avviare il runner:

```bash
cd functions
npm run migration:course-model -- \
  --project=fit-rope-app-1f575 \
  --scope=all \
  --dry-run \
  --report-dir=.context/migrations/prod-2026-08-26-1800-dry-run
cd ..
```

`--dry-run` è la modalità predefinita, ma va indicata esplicitamente nei comandi
operativi per rendere evidente che non sono previste scritture.

Il comando stampa soltanto un riepilogo JSON, senza dati personali. Un esempio
di forma dell'output è:

```json
{
  "mode": "dry-run",
  "project": "fit-rope-app-1f575",
  "reportDir": ".context/migrations/prod-2026-08-26-1800-dry-run",
  "counts": {
    "course:CONVERTIBLE": 1964,
    "course:IGNORED": 11,
    "user:CONVERTIBLE": 58,
    "user:IGNORED": 447
  }
}
```

I numeri mostrati sono la baseline del 26 agosto 2026. Una scansione successiva
può produrre valori differenti: ogni variazione va spiegata, non forzata per
farla coincidere con la baseline.

## 8. Controllare gli artefatti del dry-run

La directory deve contenere:

```text
manifest.jsonl
users-migration-report.csv
courses-migration-report.csv
enrollment-integrity-report.csv
```

Verificare proprietario e permessi:

```bash
ls -la .context/migrations/prod-2026-08-26-1800-dry-run
```

Directory e file sono creati rispettivamente con permessi `0700` e `0600`.
Gli artefatti sono tre CSV e un manifest JSONL.

Il manifest contiene decisioni, target e fingerprint delle sorgenti. Non va
modificato manualmente e non va aperto/salvato con Excel. Per congelarne
l'identità durante la revisione si può registrare l'hash nella stessa directory
privata:

```bash
shasum -a 256 \
  .context/migrations/prod-2026-08-26-1800-dry-run/manifest.jsonl
```

## 9. Revisionare i CSV

`users-migration-report.csv` contiene tutti gli utenti valutati e può contenere
email, nome, telefono e altri dati personali. È UTF-8 con BOM, usa `;` come
separatore e serializza le liste come JSON nelle celle.

La revisione deve includere:

1. conteggio totale di corsi e utenti;
2. conteggio per `conversion_status` e `reason_code`;
3. controllo a campione di ogni matrice di conversione;
4. revisione di tutti i `TARGET_CONFLICT`;
5. revisione degli utenti attivi/correnti esclusi;
6. conferma che Hey Mamma rimanga escluso e invariato;
7. verifica dei `FUTURE_START` e delle date calcolate in Europe/Rome;
8. conferma del piano target, frequenza e intervallo di ogni utente convertibile.

`enrollment-integrity-report.csv` non contiene modifiche proposte: è un audit
dei riferimenti esistenti. Le anomalie su corsi futuri (`BLOCKER`) impediscono
il successo di `--verify`; le anomalie esclusivamente storiche (`WARNING`)
devono comunque essere revisionate. Il fingerprint del manifest include
`courses`, `waitlistCourses`, `cancelledEnrollments` ed
`enrollmentConsumption`: se uno di questi campi cambia prima dell'apply,
l'utente viene classificato `SOURCE_DRIFT` e non viene scritto.

Il dry-run PRD del 16 settembre ha trovato un
`SUBSCRIBED_COUNT_MISMATCH` su un corso futuro (`subscribed=7`, sei riferimenti
utente). Prima del dry-run definitivo, ricontrollare corso e sei riferimenti
nei dati correnti e stabilire il valore corretto. Usare
`recountCourseSubscribed` solo se il conteggio dei riferimenti è affidabile;
poi rifare il dry-run. Una sola approvazione dell'anomalia non rende verde
`--verify`: il runner restituisce codice 2 finché esiste un `BLOCKER`.

Codici di esclusione utente attesi:

| Codice | Significato operativo |
|---|---|
| `HEY_MAMMA` | record storico escluso dalla migrazione automatica |
| `ROLE_NOT_USER` | ruolo diverso da `User` o assente |
| `INVALID_ENTRY_BALANCE` | saldo ingressi negativo, assente o non intero |
| `ENTRY_BALANCE_EXCEEDS_PLAN` | saldo superiore al massimale del piano target |
| `FUTURE_BOOKING_NOT_COVERED` | prenotazione futura fuori famiglia o finestra target |
| `INVALID_LEGACY_TYPE` | tipologia legacy assente o sconosciuta |
| `INVALID_TAG_SHAPE` | tag mancanti, ambigui o non esatti |
| `INVALID_WEEKLY_FREQUENCY` | frequenza diversa da 2, 3 o `null` |
| `MISSING_END_DATE` | scadenza assente o non interpretabile |
| `FUTURE_START` | data iniziale nominale successiva al dry-run |
| `EXISTING_SUBSCRIPTION_CONFLICT` | esiste già una subscription OPEN incompatibile |

Non approvare il manifest finché ogni differenza rispetto alla baseline o alla
matrice non è stata spiegata. Conservare l'esito della revisione senza copiare i
dati personali in documenti versionati.

## 10. Freeze prima dell'apply

Subito prima dell'apply:

1. attivare il breve freeze concordato sulle modifiche a corsi e abbonamenti;
2. verificare che le Functions tolleranti V1/V2 siano già pubblicate;
3. verificare che le rules strette non siano ancora state pubblicate;
4. confermare che l'export Firestore sia completo;
5. confrontare nuovamente l'hash del manifest con quello revisionato;
6. annotare commit applicativo, project ID, run ID e operatore.

Se il dry-run è diventato vecchio o sono avvenute modifiche rilevanti, non
riutilizzarlo: generarne e revisionarne uno nuovo.

Questa non è una precauzione formale. La classificazione `FUTURE_START` confronta
la data iniziale nominale dell'abbonamento con l'istante del dry-run, e il
fingerprint del manifest **non** copre quell'istante: un manifest vecchio viene
applicato con le decisioni congelate, senza produrre `SOURCE_DRIFT`. Misurato
sullo stesso export a dodici giorni di distanza: 74 utenti convertibili invece di
58, cioè 16 utenti che un manifest vecchio avrebbe lasciato indietro in silenzio.
Regola: manifest prodotto e applicato nella stessa finestra; se passa più di un
giorno, rifare il dry-run e riconfrontare gli hash.

## 11. Applicare i corsi

È consigliato applicare prima i corsi usando il manifest completo revisionato:

```bash
cd functions
npm run migration:course-model -- \
  --project=fit-rope-app-1f575 \
  --scope=courses \
  --apply \
  --manifest=.context/migrations/prod-2026-08-26-1800-dry-run/manifest.jsonl \
  --confirm-project=fit-rope-app-1f575 \
  --report-dir=.context/migrations/prod-2026-08-26-1830-apply-courses
cd ..
```

Il runner aggiorna soltanto i corsi `CONVERTIBLE` del manifest. Prima di ogni
scrittura confronta fingerprint, stato V2 e precondizione di update.

## 12. Applicare gli utenti

Dopo aver controllato il riepilogo dell'apply corsi, applicare gli utenti con lo
stesso manifest:

```bash
cd functions
npm run migration:course-model -- \
  --project=fit-rope-app-1f575 \
  --scope=users \
  --apply \
  --manifest=.context/migrations/prod-2026-08-26-1800-dry-run/manifest.jsonl \
  --confirm-project=fit-rope-app-1f575 \
  --report-dir=.context/migrations/prod-2026-08-26-1845-apply-users
cd ..
```

Per ogni utente il runner crea la subscription e aggiorna lo snapshot nella
stessa transazione. L'ID ha forma `legacy_open_<document-id>`. Le subscription
già scadute vengono conservate nella collezione ma non aggiunte allo snapshot
`activeSubscriptions`.

## 13. Interpretare l'apply

L'output JSON contiene un conteggio per stato:

| Stato | Significato | Azione |
|---|---|---|
| `APPLIED` | scrittura completata | includere nel controllo successivo |
| `ALREADY_APPLIED` | target identico già presente | nessuna scrittura; esito idempotente |
| `SKIPPED` | record non convertibile nel manifest | verificare che l'esclusione fosse approvata |
| `SOURCE_DRIFT` | sorgente cambiata o scomparsa dopo il dry-run | non sovrascritto; riesaminare e rifare dry-run |
| `TARGET_CONFLICT` | esiste un V2/subscription incompatibile | non sovrascritto; risolvere manualmente |

Importante: `--apply` termina con codice 0 anche se il riepilogo contiene
`SOURCE_DRIFT` o `TARGET_CONFLICT`. Il codice di uscita non sostituisce la
revisione del JSON e dei CSV generati dall'apply.

In presenza di drift o conflitti:

1. non correggere il manifest;
2. non forzare scritture manuali durante la stessa sessione;
3. identificare la modifica concorrente;
4. decidere la correzione con il responsabile del dato;
5. produrre un nuovo dry-run per i record interessati.

## 14. Verificare il risultato

Eseguire una nuova scansione completa:

```bash
cd functions
npm run migration:course-model -- \
  --project=fit-rope-app-1f575 \
  --scope=all \
  --verify \
  --report-dir=.context/migrations/prod-2026-08-26-1900-verify
cd ..
```

`--verify` controlla:

- record ancora `CONVERTIBLE`;
- target V2 in conflitto;
- subscription con famiglia `HYROX` o piano `hyrox_*`;
- snapshot utente HYROX.
- anomalie `BLOCKER` nell'audit integrità delle iscrizioni.

Codici di uscita:

| Codice | Significato |
|---:|---|
| 0 | nessun record migrabile/conflitto, residuo HYROX o blocker di integrità |
| 1 | errore di configurazione, credenziali, argomenti o runtime |
| 2 | verifica fallita: migrazioni/conflitti, residui HYROX o blocker presenti |

I record `IGNORED` approvati non fanno fallire automaticamente `--verify`. Il
gate sugli utenti attivi esclusi resta quindi una verifica gestionale obbligatoria
basata sul CSV, non soltanto sul codice di uscita.

## 15. Verificare l'idempotenza

Dopo un apply riuscito è possibile rilanciare lo stesso comando con lo stesso
manifest. Il risultato atteso è `ALREADY_APPLIED` per i convertiti e `SKIPPED`
per gli esclusi, con zero nuove scritture.

Un risultato diverso indica drift o conflitto e deve essere analizzato prima di
proseguire con web app e rules.

## 16. Completare il rollout PRD

I conteggi del [dry-run del 16 settembre](DRY_RUN_PRD_2026-09-16.md) e lo
stato «zero subscription, zero corsi V2» verificato l'8 settembre sono
fotografie storiche. Non descrivono lo stato live al momento del cutover.

1. Da un commit approvato di `develop`, eseguire i gate locali della sezione 3
   e pubblicare le Functions tolleranti V1/V2 con
   `firebase deploy --project prod --only functions`. Verificare su PRD con
   `firebase functions:list --project prod` le callable
   `subscribeToCourse`, `unsubscribeFromCourse`, `joinWaitlist`,
   `leaveWaitlist`, `assignSubscription`, `deleteCourse`,
   `recountCourseSubscribed`, `createManagedUser`, `grantSignupTrial`,
   `previewLegacyUserMigration`, `migrateLegacyUser`,
   `sendOneSignalNotification`, `ensureOneSignalUser`,
   `removeOneSignalEmail` e la HTTP `courseIcs`. Verificare anche
   `firestoreBackupDaily` e `firestoreBackupDailyCheck`. Le funzioni
   `sendTestCertificateEmail` e `certificateEmailsDaily` sono solo staging e
   devono essere assenti su PRD.
2. Ricontrollare ogni blocker futuro dell'audit come nella sezione 9. Prima
   di un eventuale `recountCourseSubscribed` creare e verificare un export di
   sicurezza; dopo la correzione, creare un nuovo export dello stato da
   migrare. Scaricare quest'ultimo e ripetere la sequenza su emulatori della
   sezione 21 prima dell'apply PRD.
3. Eseguire un nuovo dry-run completo, revisionare manifest e tre CSV con un
   secondo operatore, registrare l'hash e approvare le esclusioni. Se il
   manifest supera un giorno di età o cambiano i dati, rifare dry-run e
   revisione nella stessa finestra dell'apply.
4. Concordare e comunicare la finestra di manutenzione. Servire una pagina di
   manutenzione ai nuovi accessi web, sospendere registrazioni e operazioni
   gestionali (creazione/modifica corsi e utenti, assegnazioni), e far
   chiudere le schede già aperte a staff e operatori. Il freeze è operativo:
   la pagina di manutenzione non spegne le schede già aperte e il runner non
   blocca le scritture dei client. Se non si può assicurare questa
   sospensione, fermarsi prima dell'apply e predisporre un blocco tecnico
   delle scritture.
5. Confrontare l'hash, quindi applicare corsi e utenti dal manifest approvato.
   `SOURCE_DRIFT` e `TARGET_CONFLICT` impongono lo stop anche con exit code 0.
6. Dalla root del repository eseguire
   `node scripts/reconcile_subscription_model_version.js --project=fit-rope-app-1f575`
   sui profili già V2 senza marker; revisionare `safe` e `manual`, poi applicare
   solo `safe` durante il freeze aggiungendo
   `--apply --confirm-project=fit-rope-app-1f575`. Risolvere i `manual`
   separatamente: lo script non li modifica.
7. Eseguire `--verify --scope=all`: attesi `failures: 0`, zero residui HYROX,
   `enrollmentBlockers: 0` ed exit code 0. Ripetere l'apply con lo stesso
   manifest: convertiti `ALREADY_APPLIED`, esclusi `SKIPPED`, zero scritture.
8. Eseguire `flutter build web --release` (dart2js, non `--wasm`), pubblicare `build/web/` su
   Hostinger e subito dopo eseguire
   `firebase deploy --project prod --only firestore:rules` nella stessa
   finestra. La web nuova con rules vecchie non può registrare
   utenti; la web vecchia con rules nuove fallisce sulla registrazione e sulla
   creazione utenti. Comunicare a tutti la chiusura e riapertura delle schede;
   il controllo di `version.json` in `web/index.html` tenta il reload ma non
   garantisce l'aggiornamento immediato di una scheda già aperta. Tenere
   sospese le operazioni finché l'upload, le rules e un accesso fresco al sito
   non sono verificati.
9. Rieseguire `--verify`, poi smoke funzionale con account di prova controllati:
   registrazione, creazione utente Admin, iscrizione/disiscrizione e rimborso
   nei piani Prova, Pacchetto e Frequenza. Verificare la versione caricata
   riaprendo il sito e controllando il `version.json` pubblicato; raccogliere
   conferma dallo staff che le schede precedenti siano state chiuse.
10. Bonificare gli utenti attivi/correnti esclusi. La card Admin di
    `UserDetailPage` gestisce i profili `User` `AUTO_CONVERTIBLE` o
    `MANUAL_REQUIRED` su ogni breakpoint; `CONFLICT` è sola lettura. Se un
    profilo escluso o già migrato ha default pendenti, la card espone
    `NORMALIZE`; ruoli espliciti e tag ambigui restano invariati. Documentare e
    approvare separatamente le esclusioni di conversione. Gate:
    nessun utente corrente senza subscription valida o esclusione approvata.
11. Rimuovere il freeze solo dopo smoke e gate degli esclusi. La rimozione del
    ramo legacy e del dual-write appartiene a una modifica successiva.

## 17. Rollback e arresto sicuro

Il runner non include un comando di rollback. In caso di risultato inatteso:

1. interrompere il rollout prima di web app e rules;
2. mantenere il freeze;
3. conservare report, manifest e log nella directory privata;
4. identificare con precisione le scritture `APPLIED`;
5. concordare il ripristino dall'export Firestore o uno script inverso revisionato.

L'export non comprende Firebase Auth, rules, indici o TTL. L'import non elimina
documenti creati dopo il backup: seguire la procedura di
[backup e ripristino](../../operations/FIRESTORE_BACKUP_RESTORE.md), che prevede
una destinazione temporanea per la verifica e, per il ripristino esatto su
`(default)`, freeze, nuovo export di sicurezza e svuotamento controllato.

Non cancellare manualmente subscription e snapshot: la migrazione utente è
atomica e un rollback parziale può rendere incoerente la fonte di verità. I campi
legacy non vengono eliminati dall'apply, quindi le Functions V1/V2 permettono di
fermarsi e investigare prima delle fasi irreversibili successive.
Se il problema emerge dopo web e rules, mantenere la pagina di manutenzione e
coordinare anche il ripristino di web/rules con lo stato dati scelto: il solo
import Firestore non ripristina il client né le regole.

## 18. Riferimento CLI

| Argomento | Obbligatorio | Valori/uso |
|---|---|---|
| `--project` | sempre | project ID Firebase reale |
| `--scope` | no | `courses`, `users`, `all`; default `all` |
| `--dry-run` | una modalità | default se nessuna modalità è specificata |
| `--apply` | una modalità | scrive solo dal manifest |
| `--verify` | una modalità | scansione read-only con gate |
| `--report-dir` | raccomandato | deve stare sotto `.context/migrations/` |
| `--manifest` | con `--apply` | JSONL di un dry-run, sotto `.context/migrations/` |
| `--confirm-project` | con `--apply` | deve coincidere esattamente con `--project` |

Le modalità sono mutuamente esclusive. Il runner non supporta attualmente
`--help`: argomenti inattesi o valori non validi terminano con codice 1.

## 19. Problemi comuni

### `--project e obbligatorio`

Passare il project ID reale dopo `--` nel comando npm.

### Modulo `functions/lib/migration/...` non trovato

Eseguire `npm run build` in `functions/`, oppure usare
`npm run migration:course-model`, che compila automaticamente.

### Credenziali o permessi negati

Verificare ADC con `gcloud auth application-default print-access-token`, account,
project ID e ruoli Firestore. Non sostituire le ADC con file di chiavi nel repo.

### Directory report o manifest rifiutata

Usare un percorso discendente da `.context/migrations/`. Questa restrizione è
intenzionale e non va aggirata.

### Verify termina con codice 2

Leggere `failures`, `hyroxSubscriptions`, `hyroxSnapshots` e i CSV di verifica.
Il codice 2 segnala un gate non soddisfatto, non un crash del runner.

Il gate include anche `enrollmentBlockers > 0`. Il dry-run PRD del 16 settembre
ne riportava uno: se è ancora presente, `--verify` termina con 2 anche dopo un
apply senza conflitti. Non considerarlo un successo del rollout: risolvere il
blocker e ripetere il dry-run prima dell'apply. Gli esclusi approvati compaiono
come `IGNORED` nel verify e `SKIPPED` nell'apply.

### Apply termina con codice 0 ma mostra conflitti

L'apply ha completato il batch senza errori runtime, ma i record protetti non
sono stati sovrascritti. Trattare `SOURCE_DRIFT` e `TARGET_CONFLICT` come stop
operativi e produrre un nuovo piano per quei record.

## 20. Checklist di chiusura

- [ ] commit e versione del runner registrati
- [ ] export Firestore completato e verificato
- [ ] callable PRD verificate, funzioni solo staging assenti
- [ ] blocker futuri risolti dopo controllo dei riferimenti utente
- [ ] replay dell'export su Emulator completato
- [ ] dry-run completo revisionato da almeno un secondo operatore
- [ ] hash del manifest approvato registrato privatamente
- [ ] nessun dato personale copiato in Git o nella PR
- [ ] apply corsi senza drift/conflitti non risolti
- [ ] apply utenti senza drift/conflitti non risolti
- [ ] reconcile V2 senza marker eseguito, casi `manual` risolti o registrati
- [ ] prima verifica con codice 0
- [ ] finestra di manutenzione attiva, staff fuori dalle schede precedenti
- [ ] web app e rules pubblicate nella stessa finestra, build fresca verificata
- [ ] seconda verifica con codice 0
- [ ] smoke funzionale con account controllati completato
- [ ] Trainer non vedono la creazione utenti Admin-only
- [ ] utenti attivi esclusi bonificati o approvati esplicitamente
- [ ] freeze rimosso soltanto dopo il controllo funzionale
- [ ] report conservati secondo le regole interne di accesso e retention

## 21. Prova su replay dell'export nell'emulatore

Questa procedura permette di provare l'intera sequenza batch (dry-run, apply,
verify, apply idempotente) su dati di produzione reali senza toccare nulla in
cloud e senza clonare PRD dentro Firestore staging. È il modo raccomandato per
validare il meccanismo e per revisionare i report prima di chiedere una finestra
operativa.

Copre tutto ciò che passa dal runner. **Non** copre le callable della migrazione
guidata né la UI Admin: per quelle serve ancora il clone su staging descritto
nell'handoff.

### 21.1 Verificare la copia locale dell'export

```bash
cd /Users/Frank/Backups/FitRope/firestore/prod/<data>/<run-id>
shasum -a 256 -c checksums.sha256
```

Non proseguire se un solo file non risulta `OK`.

### 21.2 Avviare l'emulatore con l'export

Richiede Java 21 nel PATH. Puntare alla directory che contiene
`<run-id>.overall_export_metadata`:

```bash
PATH="/usr/local/opt/openjdk@21/bin:$PATH" firebase emulators:start \
  --project fit-rope-app-1f575 --only firestore \
  --import=/Users/Frank/Backups/FitRope/firestore/prod/<data>/<run-id>/<run-id>
```

Il project ID è quello reale di produzione, ma con `emulators:start` resta
locale: nessun contatto col cloud. Usare lo stesso valore nel runner, così i due
lati concordano.

### 21.3 Guardia contro le scritture in produzione

**Un `--apply` senza `FIRESTORE_EMULATOR_HOST` scrive in produzione.** Non
eseguire il runner a mano durante la prova: passare da un wrapper che rifiuti di
partire se l'emulatore non risponde su `localhost:8080` e se non contiene lo
snapshot atteso, e che esporti la variabile lui stesso. Copia di lavoro in
`.context/sim/guard.sh`, se presente sulla postazione; `.context` non è
versionata e il wrapper va verificato prima dell'uso.

### 21.4 Fotografare gli invarianti prima dell'apply

La migrazione non deve toccare `courses`, `waitlistCourses`,
`cancelledEnrollments` ed `enrollmentConsumption` sugli utenti, né `subscribed`,
`waitlist`, `capacity` e `startDate` sui corsi. Prima dell'apply salvare un hash
per documento di quei campi e riconfrontarlo alla fine: è l'unica prova diretta
che l'invariante è stata rispettata. Script di riferimento in
`.context/sim/snapshot.js`, se disponibile sulla postazione.

### 21.5 Eseguire la sequenza

Gli stessi comandi delle sezioni 7, 11, 12, 14 e 15, con la guardia davanti e
`--project=fit-rope-app-1f575`. La copia locale non versionata
`.context/sim/run-simulation.sh`, se disponibile e verificata, li esegue in
ordine, incorpora la guardia, fotografa e riconfronta gli invarianti e spegne
l'emulatore alla fine. Se manca, predisporre e revisionare una guardia con i
controlli della sezione 21.3 prima di qualsiasi apply sul replay:

```bash
.context/sim/run-simulation.sh <dir-import> <prefisso-run-id>
```

Esito atteso su un export sano:

| Passo | Atteso |
|---|---|
| dry-run | manifest generato, conteggi coerenti con la revisione |
| apply corsi | tutti `APPLIED` o `SKIPPED`, zero `SOURCE_DRIFT`/`TARGET_CONFLICT` |
| apply utenti | come sopra |
| verify | `failures: 0`, zero residui HYROX e blocker, convertiti `ALREADY_APPLIED`, esclusi `IGNORED` |
| apply ripetuto | convertiti `ALREADY_APPLIED`, esclusi `SKIPPED`, zero nuove scritture |
| invarianti | zero documenti modificati nel confronto prima/dopo |

### 21.6 Chiudere la prova

Spegnere l'emulatore: lo stato è in memoria e sparisce, non serve alcun
ripristino. Verificare poi con una lettura read-only, **senza**
`FIRESTORE_EMULATOR_HOST`, che lo stato PRD corrisponda alla fotografia presa
prima della prova; non assumere che subscription e corsi V2 siano ancora zero.
Conservare i report sotto `.context/migrations/` con
i permessi soliti.
