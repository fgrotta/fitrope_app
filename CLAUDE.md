# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `agents.md`.

## Comandi

### Flutter

```bash
flutter pub get          # installa dipendenze
flutter test             # esegui tutti i test
flutter analyze --no-fatal-infos  # gate CI: gli info restano visibili
dart format --set-exit-if-changed .     # check formattazione
flutter build web --wasm --release      # build web come CI
flutter run -d chrome                   # avvio locale
```

### Cloud Functions (functions/)

```bash
cd functions
npm ci                   # installazione riproducibile (runtime Functions Node 22; unit CI verifica anche Node 24)
npm run build            # compila TypeScript
npm test                 # Jest (handler OneSignal + dominio enrollment)
npm run test:integration # test integrazione su Emulator Suite (richiede Java 21 nel PATH)
```

### Ambiente di test locale (Firebase Emulator Suite)

Il QA manuale si fa sull'emulatore, MAI in produzione (vedi `docs/AMBIENTI_DI_TEST.md`).
Richiede Java 21+ (keg-only via Homebrew: anteporre al PATH).

```bash
cd functions && npm run build && cd ..
# --project OBBLIGATORIO: vedi nota sotto
PATH="/usr/local/opt/openjdk@21/bin:$PATH" firebase emulators:start --project fit-rope-app-1f575
cd functions && npm run seed:emulator    # dati sintetici (password utenti: test1234)
flutter run -d chrome --dart-define=USE_EMULATOR=true                 # app contro gli emulatori
```

**Passare sempre `--project fit-rope-app-1f575`.** `.firebaserc` non ha un alias `default`
(solo `prod` e `staging`), quindi senza il flag la Emulator Suite parte su
`demo-no-project`, mentre `scripts/seedEmulator.js` e `lib/firebase_options.dart` puntano
entrambi a `fit-rope-app-1f575`. L'Auth emulator segrega gli account per progetto: il seed
scrive in un progetto e l'app cerca nell'altro, quindi **il login fallisce con "Email o
password sbagliati"** anche con le credenziali giuste. Per diagnosticare:
`curl -s "http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/fit-rope-app-1f575/accounts:query" -H "Authorization: Bearer owner" -H "Content-Type: application/json" -d '{}'`
(idem con `Bearer owner` sul Firestore emulator per leggere i documenti bypassando le rules).

Nel codice functions usare SEMPRE `import { Timestamp, FieldValue } from "firebase-admin/firestore"`
(il namespace `admin.firestore.*` perde le statiche nel runtime emulato).

### Deploy e gestione secret

```bash
# Produzione: il predeploy compila automaticamente via tsc
firebase deploy --project prod --only functions

# Staging: normalmente NON si deploya a mano (lo fa staging.yml su push a develop,
# vedi sotto). Percorso manuale solo per emergenze/debug, richiede prima
# functions/.env.fit-rope-staging
firebase deploy --project staging --only functions
# Il seed sta in functions/ e richiede credenziali: ADC (gcloud auth
# application-default login) oppure GOOGLE_OAUTH_ACCESS_TOKEN come in CI
cd functions && STAGING_PROJECT_ID=fit-rope-staging npm run seed:staging && cd ..

# Deploy delle firestore.rules — SEMPRE DOPO functions e web nuova
# (bloccano le scritture dirette del client vecchio; vedi docs/AVANZAMENTO)
firebase deploy --only firestore:rules

# Aggiornare il secret OneSignal REST API Key
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
firebase deploy --only functions   # re-deploy per bindare il nuovo valore

# Vedere i log runtime
firebase functions:log --only sendOneSignalNotification

# Eliminare la function
firebase functions:delete sendOneSignalNotification
```

Dopo ogni modifica, esegui almeno `flutter test`, `flutter analyze --no-fatal-infos` e `dart format --set-exit-if-changed .`. Se tocchi `functions/`, esegui anche `npm run build` e `npm test` nella cartella `functions/`; per callable, rules o transazioni aggiorna ed esegui anche `npm run test:integration`.

### Ambiente Staging (automatico su `develop`)

Staging è un **progetto Firebase separato** (`fit-rope-staging`, alias `staging` in
`.firebaserc`) con Auth, Firestore e Functions propri. Il deploy è **interamente
automatico**: ogni push o merge su `develop` fa girare `.github/workflows/staging.yml`.
Non serve (e non si deve) deployare staging a mano.

- Sito: <https://fgrotta.github.io/fitrope_app/> (GitHub Pages del fork, pubblicato
  dall'artifact del workflow via `actions/deploy-pages`, build_type `workflow` — nessun
  job scrive su un branch `gh-pages`). **Non** è produzione: la prod è Hostinger, deploy
  manuale.
- Il client sceglie l'ambiente a compile-time: `--dart-define=APP_ENV=staging` →
  `lib/app_environment.dart` espone `isStaging` e `main.dart` usa
  `StagingFirebaseOptions` invece di `DefaultFirebaseOptions`. La config Firebase staging
  **non è nel repo**: arriva da GitHub `vars` via `--dart-define` (vedi sotto).

**Ordine dei job — è vincolante, non cosmetico** (`concurrency: staging-deploy` con
`cancel-in-progress`, quindi un push nuovo annulla il deploy in corso):

1. in parallelo `flutter-test-and-build` (test + analyze + format + build web staging +
   upload artifact Pages), `functions-test` (Node 24) e `functions-integration`
   (Node 22 + Java 21 + Emulator Suite)
2. `deploy-functions` — **le callable devono esistere prima della web nuova**; subito dopo
   il seed dei dati sintetici staging
3. `deploy-pages` — pubblica il sito
4. `deploy-rules` — **le rules per ULTIME**: bloccano le scritture dirette del client, se
   uscissero prima romperebbero i client ancora sulla build vecchia
5. `smoke-test` — `curl` su `index.html`, `version.json`, `flutter_bootstrap.js` del sito
   Pages + `firebase functions:list` con assert sulla presenza di tutte le callable
   enrollment. Serve a intercettare un deploy Functions parziale, che altrimenti
   passerebbe silenzioso e romperebbe l'app al primo click.

**Autenticazione: OIDC / Workload Identity Federation, nessuna service-account key nel
repo.** I job di deploy usano `google-github-actions/auth@v3` con
`vars.GCP_WORKLOAD_IDENTITY_PROVIDER` + `vars.GCP_STAGING_DEPLOY_SERVICE_ACCOUNT` e
richiedono `permissions: id-token: write`. Il seed non usa l'ADC ma un access token
federato: `functions/scripts/seedStaging.js` legge `GOOGLE_OAUTH_ACCESS_TOKEN`
(valorizzato con `gcloud auth print-access-token`) e istanzia `Firestore` da
`@google-cloud/firestore`.

**Ogni job che legge `vars` staging deve dichiarare `environment: staging`**, e
`STAGING_PROJECT_ID` è definita **per job** (non a livello di workflow): omettendola il
job la legge vuota e il comando `firebase` fallisce in modo poco chiaro. Vars richieste
nell'environment `staging`: `FIREBASE_STAGING_{API_KEY,APP_ID,MESSAGING_SENDER_ID,PROJECT_ID,AUTH_DOMAIN,STORAGE_BUCKET}` (+ `FIREBASE_STAGING_MEASUREMENT_ID`, opzionale: è l'unica che il workflow non valida con `test -n`),
`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_STAGING_DEPLOY_SERVICE_ACCOUNT`,
`ONESIGNAL_APP_ID`, `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`.

**Node**: `functions/package.json` dichiara `engines: ">=22 <25"` e `firebase.json` fissa
`"runtime": "nodejs22"`. I job che esercitano il runtime reale (integrazione, deploy)
girano su **22**, quelli unit su **24** per compatibilità tooling. Nel secret
dell'emulatore in CI si scrive `functions/.secret.local` (gitignored), non una env var.

`ci.yml` gira **solo sulle PR** verso `main`/`develop` e su avvio manuale: i push su
`develop` sono già validati da `staging.yml`, che ripete gli stessi gate. `release.yml`
(branch `release`) **valida soltanto** — non crea release e non pubblica niente.

## Verifica live e lezioni operative

> **Policy — salva cosa impari.** Al termine di ogni sviluppo significativo, registra le lezioni apprese (trappole dell'ambiente, errori da non ripetere, pattern utili): se hanno valore generale per il progetto aggiungile a questa sezione; in ogni caso annotale nella memoria di progetto. Così le scoperte non vanno riscoperte alla sessione successiva.

Lezioni dal lavoro di sviluppo UI (verifica delle modifiche nel browser):

- `flutter run -d web-server` **ricompila solo all'avvio o su hot-restart** (`R` da stdin). Un'istanza lanciata in background non riceve `R`: dopo ogni modifica al codice **riavvia il run** (kill della porta + relaunch), non basta ricaricare la pagina.
- Il browser serve un `main.dart.js` cache-ato: dopo il relaunch fai un **hard reload** (Cmd/Ctrl+Shift+R), altrimenti vedi il build vecchio (sintomo tipico: il default sembra sbagliato o "la modifica non ha effetto").
- Per testare i **breakpoint responsive** verifica la larghezza reale (`window.innerWidth`): il ridimensionamento della finestra può essere inaffidabile. Breakpoint in `lib/layout/breakpoints.dart` (mobile <600, tablet <900, desktop <1600, largeDesktop ≥1600).
- **Pre-commit hook**: non bypassarlo come procedura ordinaria. Se l'ambiente restituisce erroneamente SDK `0.0.0-unknown`, esegui prima manualmente gli stessi gate (`flutter test`, `flutter analyze --no-fatal-infos`, formattazione e, quando applicabile, test Functions), poi documenta il problema dell'ambiente nel commit o nella PR.

### Deploy web / aggiornamento PWA (cache stantia su iOS)

- Produzione: `https://app.fithousemonza.it`, hosting Hostinger/LiteSpeed, deploy **manuale** (`flutter build web --wasm --release` -> upload di `build/web`).
- Staging: <https://fgrotta.github.io/fitrope_app/> (GitHub Pages via `actions/deploy-pages`, nessun branch `gh-pages` coinvolto), pubblicato automaticamente da `develop` tramite `.github/workflows/staging.yml` — dettagli del flusso nella sezione "Ambiente Staging" sopra. Non sostituisce il deploy Hostinger: la build usa `APP_ENV=staging`, `--base-href /fitrope_app/` e il progetto Firebase separato. `web/.htaccess` viene copiato automaticamente in `build/web/` dal build Flutter: è il modo per far applicare regole di cache a Hostinger senza toccare il pannello (su GitHub Pages è inerte, Pages non legge `.htaccess`).
- **`main.dart.js`, `flutter_service_worker.js`, `flutter_bootstrap.js`, `flutter.js` non hanno mai un hash nel nome**: restano identici da un build all'altro (il versioning è gestito internamente dal service worker generato da Flutter via confronto hash-per-file, non dal filename). Qualsiasi cache lunga su questi file (anche solo un default del server per estensione `.js`, come i 7 giorni di default riscontrati su Hostinger/LiteSpeed) blocca i client su una versione vecchia finché la cache non scade — `web/.htaccess` la limita a 30 minuti per i file "vivi" (index.html, version.json, manifest.json + i file sopra).
- Un tentativo precedente di forzare l'update via JS (unregister di tutti i service worker + wipe di tutta la Cache Storage + reload cache-busted) è stato revertito perché causava un **reload loop infinito**: il reload rileggeva comunque `main.dart.js`/`flutter_service_worker.js` dalla cache HTTP del browser (non toccata dal wipe della Cache Storage, che è uno strato diverso), quindi il mismatch di versione si ripresentava a ogni giro. Prima di reintrodurre logica di forzatura via JS, verificare sempre che gli header di cache lato server siano già corretti — altrimenti nessuna logica JS può risolvere il problema.

### UI responsive / layout shift

- Liste di card (es. `CalendarPage`): su desktop usa griglie multi-colonna con `LayoutBuilder` (n. colonne = larghezza disponibile / larghezza-min-card) e disposizione "masonry" per gestire le altezze variabili; evita la singola colonna stretta che spreca lo spazio orizzontale.
- Per un default che dipende dal layout (es. vista mese su desktop, settimana su mobile) usa uno stato **nullable** (`bool?`) risolto a runtime con `valore ?? isDesktop(context)`: così il default segue il breakpoint ma il toggle manuale dell'utente mantiene la precedenza.
- Evita stringhe **transitorie di caricamento** dentro una `description` condivisa renderizzata riga-per-riga (`CourseCard._buildMetadata`): appaiono e poi spariscono al termine della fetch → **salto di altezza** della card a ogni rebuild. I dati finali vanno in widget stabili (pill di conteggio, dialog, box dedicato), non nei metadati testuali.

## Convenzioni

- UI in italiano. Non tradurre stringhe UI in inglese salvo richiesta esplicita.
- Localizzazione date: `it_IT` via `intl`. Usa `formatDate` da `lib/utils/format_date.dart`.
- Serializzazione manuale: se aggiungi/modifichi campi nei modelli, aggiorna sempre sia `toJson` sia `fromJson` in `lib/types/`.
- Nomi file Dart: `snake_case` (es. `home_page.dart`, `get_course_state.dart`). Il repo è stato rinominato interamente da camelCase: non reintrodurre `HomePage.dart` & co.
- Stato globale Redux minimale: non aggiungere campi a `AppState` senza necessita reale.
- Dopo mutazioni su corsi/utenti, invalida la cache (`refresh_manager`, `user_cache_manager`).
- **Filtri e tipologie nel calendario**: la lista corsi è in ordine cronologico, **senza raggruppare per `courseType`** (quell'enum conosce solo Open/PT, quindi un corso Hyrox finiva sotto l'intestazione "Open"). La tipologia reale sta sulla card come accento colore + badge, con i token in `lib/utils/course_type_style.dart` (contrasto AA con testo bianco, come `capacity_color.dart`; icona sempre presente perché il colore convive con quello della capienza). I filtri sono in `lib/components/course_filter_bar.dart` + `lib/utils/course_filters.dart` (logica pura, testata): due dimensioni in AND (Tipologia da `CourseTypes.all`, Sala da `Sale.all` + "Senza sala"), chip a **set fisso** disabilitati a conteggio 0, e **non si azzerano al cambio giorno**. Due invarianti da non rompere: un chip selezionato non va MAI disabilitato (resterebbe intrappolato dopo un cambio giorno), e i conteggi di una dimensione si calcolano applicando già il filtro dell'altra.
- Per iscrizioni, disiscrizioni, waitlist, assegnazione abbonamenti, delete e recount usa le callable in `europe-west8`: le transazioni autoritative sono nelle Cloud Functions. Le scritture client dirette restano limitate al CRUD corso consentito dalle rules.
- **Pull request**: apri sempre le PR nel fork `fgrotta/fitrope_app` con base `main`, mai verso l'upstream `dellarosamarco/fitrope_app`. Questo repo è un fork, quindi `gh pr create` di default punterebbe al parent: usa `gh pr create --repo fgrotta/fitrope_app --base main`.

## Aree sensibili

La logica di iscrizione/disiscrizione ai corsi e la parte piu critica. Se la modifichi:

1. Leggi `lib/api/courses/README_ISCRIZIONI.md`
2. Esegui i test: `flutter test`
3. File chiave: `lib/api/courses/subscribe_to_course.dart`, `unsubscribe_to_course.dart`, `lib/utils/course_unsubscribe_helper.dart`

### Notifiche OneSignal

- In staging (`APP_ENV=staging`) la Function invia email solo a UID `stg_` con email nella allowlist `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`; i payload push e tutti gli altri destinatari sono soppressi.

- REST API key **non** nel codice Flutter: sta in Google Secret Manager, usata solo dalla Cloud Function.
- Se modifichi il payload inviato a OneSignal, non includere `app_id` — lo inietta la function server-side.
- `notification_service.dart` chiama `FirebaseFunctions.instance.httpsCallable('sendOneSignalNotification')`.
- Su web le chiamate dirette a OneSignal falliscono per CORS: passa sempre dalla Cloud Function.
- **OneSignal web ATTIVO**: `web/index.html` carica il Web SDK v16 con un bridge JS completo (init, login/logout, email, push opt-in/opt-out, service worker in `web/push/onesignal/OneSignalSDKWorker.js`) e `onesignal_web.dart` è un binding `dart:js_interop` completo — NON è no-op. `main.dart` inizializza OneSignal su ogni build non-emulatore. Le email applicative continuano a passare dalla Cloud Function `sendOneSignalNotification` (vedi punto "Alias OneSignal" sotto); le push native restano attive su Android/iOS via `onesignal_flutter`. Vedi il TODO "OneSignal web" in fondo per le decisioni aperte.
- Ogni corso ha i flag `reminderEnabled` e `waitlistEnabled`: se false, `scheduleTrialReminder` / `notifyWaitlistUsers` saltano l'invio e `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`.
- **Alias OneSignal prima dell'invio**: `include_aliases: {external_id: [...]}` fallisce silenziosamente (200 OK, `recipients: 0`, nessun errore) se l'utente non ha mai fatto login — l'alias viene creato solo al login self-service (caso tipico: utente creato da Admin/walk-in e mai loggato). La garanzia è **server-side** in `sendOneSignalNotificationHandler` (`functions/src/handler.ts`): per ogni invio con `target_channel: 'email'` + `include_aliases.external_id`, la function legge l'email da Firestore (`users/{uid}`) e chiama `ensureOneSignalEmailSubscription` (idempotente) prima della POST. I call-site client NON devono più fare l'ensure prima degli invii; resta solo al login. `postToOneSignal` logga warning su 200-con-errors e `recipients: 0` (visibili con `firebase functions:log --only sendOneSignalNotification`). Nota: l'ensure riabilita anche una subscription email disattivata dal link di unsubscribe OneSignal — il filtro reale sono i flag `emailNotificationsEnabled`/`pushNotificationsEnabled` su Firestore. Gli invii server-side diretti via `postToOneSignal` (es. `certificateEmailsDaily`) devono invece chiamare l'ensure esplicitamente, come fa `runCertificateEmails`.
- **Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).
- **Debug email**: in `kDebugMode` è disponibile un FAB in `Protected` che apre `DebugEmailPage` (`/debug-email`). Permette di inviare email di test (waitlist, promemoria prova, certificato a 10 giorni / scadenza oggi) all'utente corrente senza triggering reale degli eventi. Le funzioni `sendTestWaitlistEmail` / `sendTestTrialReminderEmail` / `sendTestCertificateEmail` sono in `notification_service.dart`.
- **Email certificati — solo emulatore e staging**: `sendTestCertificateEmail` (callable di test) e `certificateEmailsDaily` (onSchedule 08:00 Europe/Rome che esegue `runCertificateEmails`: promemoria a −10 giorni e avviso il giorno della scadenza) sono **export condizionali** in `functions/src/index.ts`, presenti solo con `APP_ENV=staging` o `FUNCTIONS_EMULATOR=true`. In produzione non vengono deployate finché la feature non viene promossa. Lo smoke-test di staging.yml asserisce la loro presenza su staging.

## Struttura rapida

- Entry point: `lib/main.dart`
- Route: `lib/router.dart` (7 route statiche + 1 debug-only)
- Stato: `lib/state/` (Redux con thunk)
- Pagine: `lib/pages/welcome/` (auth) e `lib/pages/protected/` (area protetta)
- API Firestore: `lib/api/` (authentication + courses)
- Modelli: `lib/types/fitrope_user.dart`, `lib/types/course.dart`
- Layout responsive: `lib/layout/` (breakpoints + AppShell)
- Servizi esterni: `lib/services/` (OneSignal mobile + web, notifiche, email templates)
- Cloud Functions: `functions/src/` (TypeScript, proxy OneSignal)

## TODO / Da aggiornare

Punti aperti da affrontare in un secondo momento (non ancora fatti):

- **Tipologia corso: doppio binario `tags` + `courseType`**: il modello `Course` mantiene sia `tags` (fonte per eligibility, per la UI e per il supporto a Hyrox/Hey Mamma) sia `courseType` (enum legacy `open` / `personal_trainer`). Dopo il redesign del calendario l'**unico** uso residuo di `courseType` è la scelta dell'immagine di default in `CourseImages`: la UI mostra la tipologia reale via `CourseTypes.primaryForTags` + i token di `lib/utils/course_type_style.dart`. Per chiudere il doppio binario serve quindi solo dare a Hyrox e Hey Mamma immagini proprie (oggi ereditano quelle Open/PT) e poi rimuovere il campo; `CourseType.label` non è più usato in lettura.
- **OneSignal web — decisioni aperte**: (a) il Web SDK è attivo con push opt-in funzionante, ma non è tracciato se l'attivazione sia una scelta definitiva — confermare o disattivare; (b) l'appId OneSignal è **hardcoded in `lib/main.dart` ed è quello di produzione**: la build web di staging non riceve alcun `--dart-define` OneSignal, quindi la web staging registra device/utenti sull'app OneSignal di prod (non esiste una seconda app OneSignal per staging — lato Functions invece `ONESIGNAL_APP_ID` è già parametrizzato via env). Da decidere: seconda app + dart-define, oppure disattivazione dell'init su `isStaging`.
- **Test E2E da riallineare al nuovo modello** (`integration_test/`; `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` in `skip: true`, `login_test.dart` attivo ma nessun job CI li esegue):
  - `helpers/seed.dart` crea documenti direttamente e valorizza solo i `tags`; definire un seed compatibile con il modello misto e con la policy di eligibility corrente.
  - Rivalidare `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` contro Emulator Suite, con abbonamenti e callable reali invece di credenziali di produzione.
