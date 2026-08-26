# Runbook operativo della migrazione

Questa procedura descrive come usare il runner
`scripts/backfillCourseModel.js` in modo ripetibile e verificabile. Leggere prima
il [piano completo](PIANO.md).

## 1. Cosa modifica il runner

Con `--apply`, il runner può effettuare due classi di scrittura:

- `courses`: aggiunge o normalizza `courseType`, `tag`, `tags` e
  `courseModelV2` tramite `BulkWriter`;
- `users` e `subscriptions`: crea una subscription OPEN con ID deterministico e
  aggiorna `activeSubscriptions` nella stessa transazione.

Il runner non elimina i campi legacy dell'utente. I corsi e gli utenti esclusi
rimangono invariati e vengono elencati nei report.

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
```

Verificare proprietario e permessi:

```bash
ls -la .context/migrations/prod-2026-08-26-1800-dry-run
```

Directory e file sono creati rispettivamente con permessi `0700` e `0600`.

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

Codici di esclusione utente attesi:

| Codice | Significato operativo |
|---|---|
| `HEY_MAMMA` | record storico escluso dalla migrazione automatica |
| `ROLE_NOT_USER` | ruolo diverso da `User` o assente |
| `NO_EXACT_ENTRIES_PLAN` | pacchetto ingressi senza durata target esatta |
| `TRIAL_NOT_SUPPORTED` | abbonamento prova senza piano target |
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

Codici di uscita:

| Codice | Significato |
|---:|---|
| 0 | nessun record migrabile/conflitto e nessun residuo HYROX |
| 1 | errore di configurazione, credenziali, argomenti o runtime |
| 2 | verifica fallita: migrazioni/conflitti o residui HYROX presenti |

I record `IGNORED` approvati non fanno fallire automaticamente `--verify`. Il
gate sugli utenti attivi esclusi resta quindi una verifica gestionale obbligatoria
basata sul CSV, non soltanto sul codice di uscita.

## 15. Verificare l'idempotenza

Dopo un apply riuscito è possibile rilanciare lo stesso comando con lo stesso
manifest. Il risultato atteso per i record già scritti è `ALREADY_APPLIED`, con
zero nuove scritture.

Un risultato diverso indica drift o conflitto e deve essere analizzato prima di
proseguire con web app e rules.

## 16. Completare il rollout

La sequenza completa resta:

1. deploy delle Functions tolleranti V1/V2 e del nuovo catalogo;
2. export Firestore;
3. dry-run completo e revisione dei CSV;
4. freeze delle modifiche interessate;
5. apply corsi e utenti dal manifest approvato;
6. `--verify` completo;
7. deploy della nuova web app;
8. deploy delle rules strette;
9. nuovo `--verify`;
10. bonifica manuale degli utenti attivi/correnti esclusi;
11. gate: zero utenti correnti senza subscription valida o esclusione approvata;
12. solo in una modifica successiva, rimozione del ramo legacy e cleanup del
    dual-write.

Non invertire il deploy della web app e delle rules senza verificare la
compatibilità dei client in circolazione.

## 17. Rollback e arresto sicuro

Il runner non include un comando di rollback. In caso di risultato inatteso:

1. interrompere il rollout prima di web app e rules;
2. mantenere il freeze;
3. conservare report, manifest e log nella directory privata;
4. identificare con precisione le scritture `APPLIED`;
5. concordare il ripristino dall'export Firestore o uno script inverso revisionato.

Non cancellare manualmente subscription e snapshot: la migrazione utente è
atomica e un rollback parziale può rendere incoerente la fonte di verità. I campi
legacy non vengono eliminati dall'apply, quindi le Functions V1/V2 permettono di
fermarsi e investigare prima delle fasi irreversibili successive.

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

### Apply termina con codice 0 ma mostra conflitti

L'apply ha completato il batch senza errori runtime, ma i record protetti non
sono stati sovrascritti. Trattare `SOURCE_DRIFT` e `TARGET_CONFLICT` come stop
operativi e produrre un nuovo piano per quei record.

## 20. Checklist di chiusura

- [ ] commit e versione del runner registrati
- [ ] export Firestore completato e verificato
- [ ] dry-run completo revisionato da almeno un secondo operatore
- [ ] hash del manifest approvato registrato privatamente
- [ ] nessun dato personale copiato in Git o nella PR
- [ ] apply corsi senza drift/conflitti non risolti
- [ ] apply utenti senza drift/conflitti non risolti
- [ ] prima verifica con codice 0
- [ ] web app e rules pubblicate nell'ordine previsto
- [ ] seconda verifica con codice 0
- [ ] utenti attivi esclusi bonificati o approvati esplicitamente
- [ ] freeze rimosso soltanto dopo il controllo funzionale
- [ ] report conservati secondo le regole interne di accesso e retention
