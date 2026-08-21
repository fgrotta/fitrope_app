# Aree di test FitRope

Questo catalogo descrive **cosa** verificare e a quale livello. Per la scelta
degli ambienti, i limiti dell'Emulator Suite e lo staging vedere
[AMBIENTI_DI_TEST.md](AMBIENTI_DI_TEST.md).

Le sette macro-aree originarie corrispondono a: registrazione (A1), creazione
corsi (A4–A5), visualizzazione (A6–A7), iscrizione/disiscrizione (A8–A9),
waitlist (A10), dashboard (A14), ricerca e modifica utenti (A12).

## Architettura dual-target

| Binario | Responsabilità | Esecuzione |
|---|---|---|
| Flutter E2E locale | UI, Auth, rules e callable reali su dati effimeri | `flutter drive` con `USE_EMULATOR=true` |
| Flutter E2E staging | Backend e indici reali, Cloud Run e configurazione staging | `flutter drive` con `APP_ENV=staging` e config Firebase completa |
| Smoke Playwright | Bundle pubblicato, base-href, bootstrap, console e banner | URL GitHub Pages dopo `deploy-rules` |

Sul web si usa `flutter drive`, non `flutter test -d chrome`: chromedriver deve
ascoltare sulla porta 4444 e ogni invocazione riceve un solo `--target`.

### Locale

```bash
cd functions && npm ci && npm run build && cd ..
firebase emulators:start --project fit-rope-app-1f575
cd functions && npm run seed:emulator && cd ..
chromedriver --port=4444
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/login_test.dart \
  -d chrome \
  --dart-define=USE_EMULATOR=true \
  --dart-define-from-file=integration_test/test_env.emulator.json
```

`--project fit-rope-app-1f575` è obbligatorio: Auth emulator separa gli
account per project ID. Il file emulator contiene esclusivamente credenziali
sintetiche committabili con password `test1234`.

### Staging

Il job genera `integration_test/test_env.staging.json`, passa tutti i define
`FIREBASE_*`, `APP_ENV=staging` e un `TEST_RUN_NAMESPACE` univoco. Il runner
fallisce prima dell'inizializzazione se il target non è esattamente emulatore o
staging, oppure se il project ID staging non è sicuro.

Le risorse dinamiche hanno prefisso `[TEST:<run_id>:<attempt>]`. Il teardown
applicativo si ri-autentica come Admin; il runner host esegue inoltre cleanup
iniziale e finale con `if: always()` per gestire crash e cancellazioni CI.

Playwright resta volutamente uno smoke: Flutter renderizza su canvas e richiede
l'attivazione dell'albero semantics. I flussi funzionali restano in
`integration_test/`.

## Livelli

- La logica pura vive nei test Dart e Jest unitari.
- Transazioni, autorizzazione e rules vivono negli integration test Functions
  sull'Emulator Suite.
- Gli E2E verificano il cablaggio finder → callable → stato → rendering,
  senza replicare l'intera matrice di business.
- Staging copre ciò che l'emulatore non vede: indici compositi, deploy e runtime
  reale. La consegna email reale è ammessa soltanto per A16b e destinatari
  allowlisted; il push resta escluso dalla suite Chrome.

## Fixture

- Emulatore: Admin, Trainer, account disattivato, legacy
  pacchetto/mensile/prova e membro nuovo modello con Open 3x, Hyrox 10 ingressi
  e PT 10 ingressi. Gli E2E della matrice aggiungono account, corsi e
  subscription namespaced per run tramite `prepare-enrollment-matrix`.
- Staging: `stg_admin`, `stg_trainer`, `stg_disabled`, `stg_member`,
  `stg_member2`; subscription deterministiche per i percorsi usati dagli E2E.
- I corsi E2E sono creati otto giorni avanti alle 18:00 Europe/Rome, dentro la
  validità delle subscription seed; non si usano date annuali fisse.
- La registrazione usa due invocazioni: creazione e blocco non verificato,
  verifica Admin SDK dello stesso UID, login verificato e cancellazione finale.

## Catalogo

Ogni area riporta i casi minimi e il livello prevalente. “E2E” indica entrambi
i target salvo diversa indicazione.

### A1 — Registrazione

Validazioni di email, password, conferma, nome, cognome, telefono e privacy;
happy path con documento prova canonico; rules self-create; email duplicata;
login bloccato prima della verifica e riuscito dopo verifica Admin SDK.
Copertura rules esistente; orchestrazione E2E bifase presente.

### A2 — Login, logout e sessione

Credenziali valide/errate, utente inattivo, email non verificata, reset password,
persistenza dopo restart, logout e redirect splash. Login, inattivo, persistenza
e logout sono nel gate E2E; reset password resta da coprire end-to-end.

### A3 — Ruoli e navigazione

Destinazioni User/Trainer/Admin, dashboard desktop-only, route gestionali
protette, permessi su dettaglio utente e azioni corso, esclusione dello staff
dall'iscrizione. App shell e accesso al form corso sono coperti da widget test;
un E2E dual-target rappresentativo verifica navigazione e route diretta. Restano
da estendere i permessi granulari sul dettaglio utente.

### A4 — Corso singolo

Creazione completa, validazioni, auto-assegnazione Trainer, edit, duplica,
payload senza campi server-owned e rules. Form create/edit e ruolo Trainer sono
coperti da widget test; un E2E dual-target crea e verifica un corso reale. La
duplicazione completa resta coperta sotto il livello E2E.

### A5 — Corsi ricorrenti

Giorni selezionati, range e numero generato; rifiuto di range invertito, oltre
cinque mesi, nessun giorno e nessuna data valida. Schedule e validazioni sono
coperti da test puri/widget; l'E2E dual-target crea una serie e ne verifica i
documenti namespaced e il cleanup.

### A6 — Calendario

Vista mese/settimana per breakpoint, marker, conteggi, filtri, grouping,
colonne responsive, empty state, cache e cutoff. I documenti con `uid` canonico
o solo `id` legacy sono accettati; soltanto quelli senza entrambi sono scartati.
Toggle responsive, filtri, reset giorno ed empty state sono coperti da widget
test; loader e cutoff hanno test unitari.

### A7 — Home

Corsi futuri, waitlist, card multi-sub/legacy/assente, certificato in scadenza
ed empty state. Label e cablaggio UI sono coperti da unit/widget test, incluso
il certificato quando l'utente non ha un abbonamento.

### A8 — Iscrizione

Percorsi prova, pacchetto, temporale, FREQUENCY Open, ENTRIES Hyrox/PT, tipo
senza famiglia e force Admin; regolamento e stati non azionabili. La matrice
pura copre Open 2x/3x/illimitato, reset settimanale, scoping di famiglia,
disiscrizioni perse, ENTRIES e ogni enum legacy. Functions copre i rifiuti e
l'emulatore la concorrenza (ultimo slot Open e ultimo ingresso ENTRIES). L'E2E
`subscription_limits_test.dart` verifica i percorsi comportamentali distinti
locale/staging con fixture isolate.

### A9 — Disiscrizione

Rimborso fuori finestra, conferma/perdita entro 8h o 4h, annullamento dialog,
retry force, consumo NONE, ledger e clamp, rimozione Admin e corso iniziato.
Dominio coperto; l'E2E critico verifica callable, rendering, ledger e rimborso
fuori finestra. I dialog e la perdita entro finestra restano coperti sotto UI e
dominio senza mutare crediti condivisi di staging.

### A10 — Lista d'attesa

Join/leave, rifiuti, ruoli esclusi, self-heal, swap completo, pulizia legacy,
rimozione Admin e deleteCourse senza notifica. Handler ed emulatore verificano
il join per Open, Hyrox, PT e legacy senza consumo e che i rifiuti non scrivano
né `course.waitlist` né `user.waitlistCourses`. Lo swap e la matrice UI sono
gate E2E critici.

### A11 — Gestione corso staff

Lista iscritti, aggiunta/rimozione, recount, delete Admin-only con rimborsi,
permessi edit/duplica e anonimato. Backend coperto; `AddSubscriberDialog` ha
widget test su filtro e force Admin. Rimozione, recount e delete restano nella
suite server, mentre il gate E2E A4 copre accesso staff e cleanup Admin.

### A12 — Ricerca e modifica utenti

Ricerca, filtri, paginazione, layout responsive, azioni riga, permessi campo
Admin/Trainer/self, diff rules, validazioni, soft delete e storico. API/rules
coperte; ricerca e filtro scadenza multi-sub hanno widget test. Paginazione,
azioni riga e permessi granulari restano da ampliare a livello UI.

### A13 — Creazione utente gestionale

Default, ruolo Admin-only, utente senza accesso, validazioni e immutabilità di
`CourseTags.defaultUserTags`. Copertura widget presente per validazioni e
creazione senza accesso; l'immutabilità dei tag è coperta a livello unit.

### A14 — Dashboard Admin

Guard desktop, aggregati utenti/corsi/subscription, scadenze, crediti, drawer,
ricerca e retry errore. Aggregati e widget principali sono coperti. Il KPI
scadenze ora include il modello multi-subscription oltre al legacy; drawer e
retry possono essere ulteriormente estesi end-to-end.

### A15 — Assegnazione abbonamenti

Visibilità Admin, catalogo, una subscription per famiglia, errori callable,
snapshot e label. Dominio coperto; il widget verifica selezione, successo ed
errore della callable iniettata. Non è ancora un flusso E2E dedicato.

### A16/A16b — Notifiche ed email certificati

Reminder prova e waitlist, preferenze, allowlist e alias OneSignal; export
certificati solo su emulatore/staging, finestre Europe/Rome e payload. La
selezione scheduler resta unit; staging può verificare la callable manuale su
un solo destinatario allowlisted.

### A17 — Regolamento e certificato

Accettazione self-only, gate prima iscrizione, banner utente e card Admin.
Rules presenti e banner certificato coperto da widget test; il dialog del
regolamento e la card Admin restano da ampliare a livello UI.

### A18 — Preferenze notifiche

Persistenza email, push, prompt e rollback richiedono una facade disattivabile.
I widget test coprono persistenza tramite operazione iniettata e rollback push;
il runner E2E mantiene OneSignal spento e non esegue ancora un salvataggio
Firestore reale per questa area.

### A19 — Piattaforma

Breakpoint, `it_IT`, DST, stabilità layout, banner staging, PWA/base-href,
service worker, header produzione e indici compositi. Gli indici e l'artefatto
pubblicato si verificano solo su staging. App shell/breakpoint sono coperti da
widget test; lo smoke Playwright abilita semantics, verifica il banner e
intercetta errori console sull'artefatto Pages.

### A20 — Anti-drift

Round-trip dei modelli, convenzioni Admin SDK, export condizionali, compatibilità
`uid`/`id`, doppio binario tags/courseType e parsing tollerante. Le differenze
volute tra ambienti hanno test espliciti; i drift accidentali si correggono.

## Selettori

Convenzione: `<area>-<elemento>[-<id>]` in kebab-case, per esempio
`registration-email-field`, `course-form-capacity-field`,
`admin-users-search-field`, `dashboard-metric-active-users` e
`subscription-card-<planKey>`. I tooltip univoci restano finder validi e non
richiedono una Key duplicata.

## Gate CI

1. PR: unit, analyze, build, Functions integration ed E2E A1/A2/A3/A4/A5/
   A8/A9/A10 su emulatore, inclusi `subscription_limits_test.dart` e
   `waitlist_subscription_matrix_test.dart`.
2. Staging: deploy Functions → Pages → rules → smoke → stessi E2E, tutti sotto
   `concurrency: staging-deploy`.
3. Cleanup staging iniziale e `if: always()` finale; la matrice rimuove prima i
   corsi tramite callable, quindi subscription, documenti utente e account
   Auth. Mai affidarsi solo ad `addTearDown`.

Restano fuori dagli E2E Chrome: push nativo, comportamento iOS del prompt,
consegna OneSignal generica e produzione. La produzione non è un target di test.
