# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `agents.md`.

## Provisioning email admin

- `checkEmailAvailability` (`functions/src/enrollment/provisioning.ts`) verifica sia i profili Firestore sia gli account Firebase Auth. La callable è pubblica per supportare la registrazione; `createManagedUser` ripete il controllo ed è l'autorità finale.
- `createManagedUser`, se riceve un'email, la normalizza in minuscolo e crea prima l'account Auth con UID del profilo; se la transazione Firestore fallisce, elimina l'account appena creato. Senza email crea soltanto il profilo.
- `setManagedUserEmail` è Admin-only: aggiunge o aggiorna Auth e Firestore con compensazione Auth se il salvataggio profilo fallisce. Non invia il reset; il client lo invia dopo il successo, e un errore di invio lascia valido il profilo per un nuovo tentativo.
- Registrazione, creazione admin e modifica admin usano `lib/utils/email_validation.dart` per normalizzazione, validazione e messaggi italiani. I nuovi indirizzi sono minuscoli; il backfill dei documenti legacy non rientra nello scope.
- Ogni nuova callback di scrittura UI deve avere `SimulationGuard.blockIfSimulating(context)` e ogni API client una `SimulationSession.assertNotSimulating(...)` prima di effetti collaterali.

## Comandi

### Flutter

```bash
flutter pub get          # installa dipendenze
flutter test             # esegui tutti i test
flutter analyze --no-fatal-infos  # gate CI: gli info restano visibili
dart format --set-exit-if-changed .     # check formattazione
flutter build web --release            # build web come CI e produzione (dart2js, NON --wasm)
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
- **`dart format` prima di `flutter pub get`**: lo stile di formattazione dipende dalla language version del pacchetto (`sdk: '>=3.5.0…'` in `pubspec.yaml`), che il formatter legge da `.dart_tool/package_config.json`. In un workspace appena creato quel file non esiste: il formatter stampa `Package resolution error when reading "analysis_options.yaml"`, ripiega sulla language version più recente e applica lo stile "tall" di Dart 3.9+, riformattando **mezzo repo** (138 file su 191) che la CI invece considera già a posto. Non è un problema di versione dell'SDK (in locale e in CI gira lo stesso Flutter 3.41.6 / Dart 3.11.4): esegui prima `flutter pub get` (o `flutter test`, che lo fa da sé) e da lì `dart format --set-exit-if-changed .` coincide col gate CI. Se compare quel warning, l'output del formatter non è attendibile: non formattare a mano per aggirarlo, la CI boccia le righe spezzate diversamente.
- **Contare le query Firestore di un flusso**: l'Emulator UI non distingue una `list` intera da una filtrata. Servi una build release (`USE_EMULATOR=true`) e caricala in un **iframe same-origin** (da `/version.json` della stessa porta): un polling ogni 2 ms su `iframe.contentWindow.firebase_firestore` chiama `setLogLevel('debug')` prima delle prime query e un wrapper su `console.*` raccoglie le righe `addTarget`, che contengono collection e filtri di ogni query. Il resume si simula con `blur`/`focus` sull'`contentWindow`. Numeri e confronto in `docs/PERF_AVVIO.md`.
- **Ripaint pigro sotto Chrome MCP**: dopo un login la route può risultare cambiata (`location.hash`) mentre il canvas mostra ancora il form e `initState` della pagina nuova non è partito; parte al primo input (un `hover` basta). Non scambiarlo per un bug di navigazione: confronta con la build di partenza nello stesso modo.
- **Pre-commit hook**: non bypassarlo come procedura ordinaria. Se l'ambiente restituisce erroneamente SDK `0.0.0-unknown`, esegui prima manualmente gli stessi gate (`flutter test`, `flutter analyze --no-fatal-infos`, formattazione e, quando applicabile, test Functions), poi documenta il problema dell'ambiente nel commit o nella PR.

### Deploy web / aggiornamento PWA (cache stantia su iOS)

- Produzione: `https://app.fithousemonza.it`, hosting Hostinger/LiteSpeed, deploy **manuale** (`flutter build web --release` -> upload di `build/web`). **Niente `--wasm`** (disattivato il 26/09/2026): vedi il punto sui `deferred` qui sotto.
- Staging: <https://fgrotta.github.io/fitrope_app/> (GitHub Pages via `actions/deploy-pages`, nessun branch `gh-pages` coinvolto), pubblicato automaticamente da `develop` tramite `.github/workflows/staging.yml` — dettagli del flusso nella sezione "Ambiente Staging" sopra. Non sostituisce il deploy Hostinger: la build usa `APP_ENV=staging`, `--base-href /fitrope_app/` e il progetto Firebase separato. `web/.htaccess` viene copiato automaticamente in `build/web/` dal build Flutter: è il modo per far applicare regole di cache a Hostinger senza toccare il pannello (su GitHub Pages è inerte, Pages non legge `.htaccess`).
- **Branding "TEST" per le build non di produzione**: `tool/apply_test_branding.py <build-dir>` marchia una build web gia' compilata — icone con banda arancione + nome `Fit House TEST` in `manifest.json`, `<title>` e `apple-mobile-web-app-title` — cosi' una PWA staging o dev installata su un dispositivo si distingue da quella di produzione. Gira **post-build** perche' `manifest.json` e `index.html` sono file statici che i `--dart-define` non vedono. E' wired in `.github/workflows/staging.yml` (step `Apply TEST branding`, con un `grep` di guardia prima dell'upload dell'artifact Pages) e in `scripts/dev_emulator.sh`; la build di produzione non lo chiama, l'assenza e' il default. Le icone sorgente sono committate in `tool/test_icons/` — **fuori da `web/`** apposta, perche' tutto cio' che sta in `web/` finirebbe nel bundle di produzione — e si rigenerano con `python3 tool/make_test_icons.py` (richiede Pillow + font bold di sistema) solo quando cambiano le icone di produzione. Il query-param `?v=` viene riscritto con un hash del contenuto delle icone: senza, una PWA staging gia' installata continuerebbe a mostrare l'icona vecchia dalla cache. Resta scoperto `flutter run -d chrome`, che non ha hook post-build.
- **`main.dart.js`, i suoi `main.dart.js_N.part.js`, `flutter_service_worker.js`, `flutter_bootstrap.js`, `flutter.js` non hanno mai un hash nel nome**: restano identici da un build all'altro. Qualsiasi cache a durata (anche solo un default del server per estensione `.js`, come i 7 giorni riscontrati su Hostinger/LiteSpeed) blocca i client su una versione vecchia. `web/.htaccess` li serve con **`Cache-Control: no-cache`** (rivalidazione a ogni caricamento, 304 grazie all'ETag) insieme a index.html, version.json, manifest.json e `AssetManifest*`/`FontManifest.json`. Non una durata, nemmeno breve: `main.dart.js` accetta solo i part con l'hash del suo build, e un `main.dart.js` vecchio in cache con un part nuovo dal server dà `DeferredLoadException` ("Impossibile caricare la pagina" sull'area protetta o sulle pagine admin). `AddType application/wasm` resta per la copia locale di CanvasKit in `canvaskit/`.
- **Build dart2js, non `--wasm`** (dal 26/09/2026): con Flutter 3.41.6 `deferred as` **non splitta il modulo wasm** (dart2wasm ha `--enable-deferred-loading`, ma `flutter_tools` non copia i moduli secondari in `build/web` e il loader dell'engine non passa `loadDeferredModule`), quindi il codice admin finiva nel bundle di tutti. Con dart2js `Protected` e il codice solo admin (`AdminUsersPage`, `AdminDashboardPage`, `UserListDrawer`, `AdminHomeSections`) sono part separati; i gate in `ci.yml`/`staging.yml` falliscono se una stringa admin ricompare in `main.dart.js` o nel part di `Protected`. Il renderer è CanvasKit (da gstatic). Prima di tornare a `--wasm` verifica che `flutter_tools` supporti il deferred loading, altrimenti la Fase 4 in `docs/PERF_AVVIO.md` non serve più a nulla.
- **Lo splash HTML** (`web/index.html`, logo `web/splash_logo.png` a 400 px) si rimuove sull'evento `flutter-first-frame`; `forceUpdate()` è un semplice `location.reload()` (lo SW di Flutter 3.41 è uno stub che si auto-deregistra, `serviceWorker.ready` non si risolveva, quindi l'auto-update era di fatto spento). Il controllo periodico di `version.json` **non ricarica mai sotto le mani dell'utente** (form non salvati): segna l'update come pendente, e il reload parte al ritorno sulla pagina (`focus` / `visibilitychange` → visible). Il reload rivalida `main.dart.js` e i part (`no-cache`), quindi arriva la versione nuova; niente loop, perché `currentVersion` riparte dal valore del server. Il database timezone è `latest_10y` (regole DST fino a gen 2029): il test "latest_10y copre l'ora legale dell'anno prossimo" diventa rosso un anno prima, e a quel punto si aggiorna il pacchetto `timezone`.
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
- **Agganciarsi a `RefreshManager`** solo con `with RefreshListenersMixin` + `listenToRefresh(cb)` in `initState`: il mixin toglie in dispose esattamente ciò che è stato registrato. Mai `addListener`/`removeListener` a mano (lo verifica `test/refresh_manager_test.dart`): HomePage ricalcolava in dispose cosa togliere da `user.role`, che `refreshCourses` cambia copiando lo store, e in simulazione restavano listener su uno State morto. `notifyRefresh` itera su una copia e salta chi viene rimosso durante il giro.
- **Filtri e tipologie nel calendario**: la lista corsi è in ordine cronologico, **senza raggruppare per `courseType`** (quell'enum conosce solo Open/PT, quindi un corso Hyrox finiva sotto l'intestazione "Open"). La tipologia reale sta sulla card come accento colore + badge, con i token in `lib/utils/course_type_style.dart` (contrasto AA con testo bianco, come `capacity_color.dart`; icona sempre presente perché il colore convive con quello della capienza). Il filtro è in `lib/components/course_filter_bar.dart` + `lib/utils/course_filters.dart` (logica pura, testata) e ha **una sola dimensione**, la Tipologia da `CourseTypes.all`: chip a **set fisso** disabilitati a conteggio 0, selezione multipla in OR, e **non si azzerano al cambio giorno**. Il primo chip è **"Tutti"**: non è una tipologia ma il set vuoto reso visibile — selezionato quando non c'è filtro, toccarlo azzera (da selezionato è un no-op: "mostra niente" non esiste), e il suo conteggio è il totale della giornata, corsi senza tipologia riconosciuta compresi. Il filtro **iniziale** lo decide `defaultTypeFilterForUser` da **ruolo + abbonamenti**, e apre il calendario sulla tipologia a cui l'utente ha davvero accesso: Admin e Trainer su "Tutti" (il ruolo vince, il loro accesso non passa dagli abbonamenti); abbonamenti *vivi* (`liveSubscriptions`, non lo snapshot grezzo) di **una sola** famiglia → la tipologia che quella famiglia sblocca via `CourseTypes.forFamily` (OPEN → Open, PT → Personal Trainer); famiglie diverse insieme → "Tutti"; nessun abbonamento vivo ma documento **legacy V1** con `fineIscrizione` ancora valida (prova, temporali, pacchetto entrate) → Open, l'unica tipologia che il modello vecchio sapeva rappresentare; un documento V2 senza abbonamenti vivi è solo scaduto → "Tutti". Si applica una volta sola in `initState`; da lì comanda l'utente. Conseguenza voluta: con il default su Open i corsi senza tipologia riconosciuta (**Hey Mamma**) non compaiono all'apertura per un socio Open che vi accede via tag legacy — restano a un tocco sul chip "Tutti". La dimensione Sala è stata rimossa dal filtro (con due sale il selettore costava più di quanto rendesse) ma `Course.sala` resta sulla card. Due invarianti da non rompere: un chip selezionato non va MAI disabilitato (resterebbe intrappolato dopo un cambio giorno), e il conteggio sul chip è per costruzione il numero di card che si vedono selezionandolo. Sotto i 900 px (`isDesktop`, la stessa soglia che decide una o due colonne) i chip scorrono in orizzontale in una riga sola, con una sfumatura via `ShaderMask` + `BlendMode.dstIn` sul lato dove resta contenuto; da 900 in su tornano in un `Wrap`. Nella barra non c'è "Azzera filtri": si deseleziona toccando il chip, il pulsante resta solo nell'empty state del filtro.
- Per iscrizioni, disiscrizioni, waitlist, assegnazione abbonamenti, delete e recount usa le callable in `europe-west8`: le transazioni autoritative sono nelle Cloud Functions. Le scritture client dirette restano limitate al CRUD corso consentito dalle rules.
- **Modalità simulazione (Admin che vede l'app come un socio)**: in simulazione
  `store.state.user` **è l'utente simulato**, ma `FirebaseAuth.currentUser` resta l'admin —
  il server autorizzerebbe davvero, quindi **il blocco read-only è client-side per
  costruzione e va aggiunto a mano a ogni nuovo percorso di scrittura**. Due layer:
  `SimulationGuard.blockIfSimulating(context)` come prima istruzione dei callback delle
  **pagine** (i bottoni devono restare colorati e cliccabili: vedere *se* sarebbero
  premibili è metà del valore diagnostico), e `SimulationSession.assertNotSimulating('<op>')`
  come **prima riga** delle funzioni in `lib/api/`, `lib/services/`, `lib/authentication/`
  (lancia anche in release). Prima di aprire la PR:
  `grep -rn "assertNotSimulating" lib/api lib/services lib/authentication`.
  Tre trappole: la guardia va **prima** di `StartLoadingAction` (dopo, il Loader resta per
  sempre) e **fuori** dai try/catch che inghiottono gli errori; un refresh asincrono non
  deve mai dispatchare `SetUserAction` con un utente catturato prima di un `await` — usa
  `dispatchUserRefreshIfCurrent` (`mounted` non dice nulla sull'identità); e chi vive fuori
  dall'albero del Navigator (la barra sta nel `builder` di `MaterialApp`) naviga con
  `appNavigatorKey`, non con `Navigator.of(context)`. Dettagli in `agents.md`.
- **Pull request**: apri sempre le PR nel fork `fgrotta/fitrope_app` con base **`develop`**, mai verso l'upstream `dellarosamarco/fitrope_app` e mai con base `main`. Questo repo è un fork, quindi `gh pr create` di default punterebbe al parent: usa `gh pr create --repo fgrotta/fitrope_app --base develop`. `develop` è il branch di integrazione (deploy staging automatico a ogni merge, vedi sopra) ed è **molto avanti** rispetto a `main`: una PR con base `main` non mostra il tuo lavoro ma decine di commit già integrati, quindi è irreviewabile. Anche i branch di feature vanno allineati a `origin/develop`, non a `main`.

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
- **OneSignal web ATTIVO**: `web/index.html` carica il Web SDK v16 con un bridge JS completo (init, login/logout, email, push opt-in/opt-out, service worker in `web/push/onesignal/OneSignalSDKWorker.js`) e `onesignal_web.dart` è un binding `dart:js_interop` completo — NON è no-op. Il SDK però **non si carica con la pagina**: lo inietta `oneSignalLoadSdk()` alla prima `oneSignalInit`, e l'unico punto che la chiama è `ensureOneSignalInitialized()` (`lib/services/onesignal_bootstrap.dart`, idempotente, esclude emulatore e staging) — da `main.dart` sul web solo se l'utente è già loggato, e da `Protected._syncOneSignalIdentity` prima di `login`. Il visitatore non loggato non scarica il SDK; su mobile l'init resta all'avvio. `__fitHouseOneSignalInitPromise` va creata **prima** di iniettare lo script, perché `login/addEmail` si accodano dietro di lei. Le email applicative continuano a passare dalla Cloud Function `sendOneSignalNotification` (vedi punto "Alias OneSignal" sotto); le push native restano attive su Android/iOS via `onesignal_flutter`. Vedi il TODO "OneSignal web" in fondo per le decisioni aperte.
- Ogni corso ha i flag `reminderEnabled` e `waitlistEnabled`: se false, `scheduleTrialReminder` / `notifyWaitlistUsers` saltano l'invio e `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`.
- **Alias OneSignal prima dell'invio**: `include_aliases: {external_id: [...]}` fallisce silenziosamente (200 OK, `recipients: 0`, nessun errore) se l'utente non ha mai fatto login — l'alias viene creato solo al login self-service (caso tipico: utente creato da Admin/walk-in e mai loggato). La garanzia è **server-side** in `sendOneSignalNotificationHandler` (`functions/src/handler.ts`): per ogni invio con `target_channel: 'email'` + `include_aliases.external_id`, la function legge l'email da Firestore (`users/{uid}`) e chiama `ensureOneSignalEmailSubscription` (idempotente) prima della POST. I call-site client NON devono più fare l'ensure prima degli invii; resta solo al login. `postToOneSignal` logga warning su 200-con-errors e `recipients: 0` (visibili con `firebase functions:log --only sendOneSignalNotification`). Nota: l'ensure riabilita anche una subscription email disattivata dal link di unsubscribe OneSignal — il filtro reale sono i flag `emailNotificationsEnabled`/`pushNotificationsEnabled` su Firestore. Gli invii server-side diretti via `postToOneSignal` (es. `certificateEmailsDaily`) devono invece chiamare l'ensure esplicitamente, come fa `runCertificateEmails`.
- **Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).
- **Debug email**: in `kDebugMode` è disponibile un FAB in `Protected` che apre `DebugEmailPage` (`/debug-email`). Permette di inviare email di test (waitlist, conferma iscrizione prova, promemoria prova, certificato a 10 giorni / scadenza oggi) all'utente corrente senza triggering reale degli eventi. Le funzioni `sendTestWaitlistEmail` / `sendTestTrialConfirmationEmail` / `sendTestTrialReminderEmail` / `sendTestCertificateEmail` sono in `notification_service.dart`. I bottoni calendario delle email di test usano un evento demo (domani 10:00-11:00): i campi "Data"/"Orario" della pagina sono testo libero e non sono parsabili.
- **Aggiungi al calendario (email prova)**: l'iscrizione di un utente `ABBONAMENTO_PROVA` genera **due** email — conferma immediata (`sendTrialEnrollmentConfirmation`) e promemoria la sera prima (`scheduleTrialReminder`) — entrambe con un deeplink Google Calendar e un link `.ics`. **OneSignal non supporta allegati email**: l'`.ics` è servito dalla function HTTP pubblica `courseIcs` (`europe-west8`), che rilegge il corso da Firestore a ogni click (`Cache-Control: no-store`). Il promemoria a −4h (`VALARM`) esiste solo nell'`.ics`, il deeplink Google non ha parametri per gli alert. La conferma è transazionale: ignora `reminderEnabled` del corso e rispetta solo `emailNotificationsEnabled` dell'utente. L'indirizzo dell'evento sta in `GYM_ADDRESS` (`functions/src/enrollment/calendarLinks.ts`), duplicato in `gymAddress` di `lib/services/calendar_links.dart` — mirror client usato solo dalle email di test: se cambia la sede vanno aggiornati entrambi.
- **Email certificati — solo emulatore e staging**: `sendTestCertificateEmail` (callable di test) e `certificateEmailsDaily` (onSchedule 08:00 Europe/Rome che esegue `runCertificateEmails`: promemoria a −10 giorni e avviso il giorno della scadenza) sono **export condizionali** in `functions/src/index.ts`, presenti solo con `APP_ENV=staging` o `FUNCTIONS_EMULATOR=true`. In produzione non vengono deployate finché la feature non viene promossa. Lo smoke-test di staging.yml asserisce la loro presenza su staging.

### WhatsApp lezioni demo (webhook Make)

- Il messaggio **non** lo manda l'app: un `POST` verso un Custom webhook Make fa partire un template WhatsApp approvato da Meta. Il testo si modifica nello scenario Make, senza deploy.
- Codice in `functions/src/whatsapp/`, un modulo per responsabilità: `phone.ts` (E.164), `format.ts` (date di Roma, riusa `romeParts` di `notify.ts`), `payload.ts` (body), `environment.ts` (gate), `makeClient.ts` (unica chiamata HTTP), `sendLog.ts` (registro invii), `demoLesson.ts` (regole destinatario e conferma), `reminders.ts` (cron), `testWebhook.ts` (callable di prova).
- Due eventi su un solo webhook, distinti dal campo `tipo`:
  - `conferma` — `EnrollmentDeps.notifyTrialWhatsapp` in `subscribeToCourseHandler`, nel blocco `if (isTrialUser)` accanto all'email di conferma e al promemoria;
  - `promemoria` — cron `sendDemoLessonWhatsappReminders`, `0 19 * * *` Europe/Rome, per le lezioni del giorno dopo.
- **"Utente di prova" è un solo predicato**, `isTrialUser` in `functions/src/enrollment/trial.ts`, usato sia dall'iscrizione sia dal cron. Non filtrare mai su `tipologiaIscrizione` da sola: chi è stato convertito al multi-abbonamento può averla ancora a `ABBONAMENTO_PROVA`.
- Il cron usa `event.scheduleTime` per scegliere i corsi del giorno dopo anche quando Cloud Scheduler ritenta l'evento. Legge gli utenti con `array-contains-any` a blocchi da 30, filtra in memoria e avvia al massimo 10 invii concorrenti. A 480 secondi ferma l'avvio di nuovi invii e fa ritentare il job; timeout della function 540 secondi. Un solo filtro Firestore per query, quindi nessun indice composito.
- **Gate `WHATSAPP_DEMO_MODE`** in `.env.<projectId>`, letto in discovery: `off` (default: nessuna function, nessun secret dichiarato), `test` (solo `sendTestDemoLessonWebhook`), `live` (+ conferma + cron). Mergiare significa deployare: il cron resta spento grazie a questo gate. La produzione è configurata in `functions/.env.fit-rope-app-1f575`, file tracciato grazie all'eccezione specifica in `.gitignore`. Su staging la modalità è `off`, a meno che `staging.yml` non la scriva; accenderla lì richiede i secret nel progetto `fit-rope-staging` e `STAGING_WHATSAPP_ALLOWLIST`, perché staging può contenere numeri reali clonati da produzione.
- **Il body è un contratto con lo scenario Make**: `{tipo, nome, numero_di_telefono, corso, giorno, orario}`, tutte stringhe non vuote (`giorno` = `15 ottobre 2026`, `orario` = `18:00`). Make impara lo schema dal primo payload: aggiungere o rinominare una chiave richiede "Redetermine data structure" sul webhook. I parametri dei template non ammettono valori vuoti, newline, tab né 4+ spazi: ci pensa `sanitizeTemplateParam`.
- La chiave di autenticazione va nell'**header `Demo-Reminder`**, non nel body; nello scenario serve "Get request headers". URL e chiave sono esclusi da ogni log (si logga solo l'host).
- Secret (l'URL del webhook **è** una credenziale):

```bash
firebase functions:secrets:set MAKE_WEBHOOK_URL --project prod
firebase functions:secrets:set MAKE_WEBHOOK_KEY --project prod
firebase functions:log --only sendDemoLessonWhatsappReminders --project prod
```

- **Idempotenza**: ogni invio è registrato in `demoLessonWebhookLog/{kind}_{userId}_{courseId}` (identificativi, istante ed esito; nessun dato personale). Il claim si crea con `create()` *prima* della POST e resta persistente. Solo `ok: true` prova che Make ha accettato la conferma e può sopprimere il promemoria nello stesso giorno di Roma. `pending`/`unknown` dopo timeout, rete, 5xx o crash non vengono reinviati automaticamente: verifica in Make prima di un eventuale intervento manuale. Solo HTTP 429 ha due nuovi tentativi nello stesso run; gli altri 4xx sono `rejected`.
- `postToMake` **non lancia mai**, non deserializza la risposta (Make risponde `Accepted` in testo) e ha un `AbortSignal.timeout`. **Gli errori a valle del webhook non tornano indietro**: numero non su WhatsApp, template non approvato, credito esaurito danno comunque `200`. Attiva le notifiche di errore dello scenario in Make.
- `sendTestDemoLessonWebhook` è **solo Admin**: una callable è raggiungibile via HTTP da qualunque utente autenticato, e ogni WhatsApp è reale e a pagamento. In `kDebugMode` la `DebugEmailPage` ha una sezione WhatsApp che la usa; il campo *Giorno* ha un formato diverso dalla *Data* delle email.
- **Anche l'emulatore locale carica `functions/.env.fit-rope-app-1f575`**, perché parte con `--project fit-rope-app-1f575`: eredita la modalità della produzione (oggi `test`, domani `live`) e, se i secret Make mancano in `functions/.secret.local`, l'emulatore li legge da Secret Manager di produzione. Per questo sull'emulatore (`FUNCTIONS_EMULATOR=true`) vale la stessa allowlist di staging: senza `STAGING_WHATSAPP_ALLOWLIST` non parte nessun WhatsApp, nemmeno dalla callable di prova. I test di integrazione girano invece su `demo-fitrope`, in modalità `off`.

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
- **OneSignal web — decisioni aperte**: (a) il Web SDK è attivo con push opt-in funzionante, ma non è tracciato se l'attivazione sia una scelta definitiva — confermare o disattivare; (b) l'appId OneSignal è **hardcoded in `lib/services/onesignal_bootstrap.dart` ed è quello di produzione**; su staging l'init è escluso (`oneSignalEnabled`) e con il caricamento lazy il SDK web non viene nemmeno scaricato, quindi la web staging non ha push (non esiste una seconda app OneSignal per staging — lato Functions invece `ONESIGNAL_APP_ID` è già parametrizzato via env). Da decidere se servono push su staging: seconda app + dart-define.
- **Test E2E da riallineare al nuovo modello** (`integration_test/`; `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` in `skip: true`, `login_test.dart` attivo ma nessun job CI li esegue):
  - `helpers/seed.dart` crea documenti direttamente e valorizza solo i `tags`; definire un seed compatibile con il modello misto e con la policy di eligibility corrente.
  - Rivalidare `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` contro Emulator Suite, con abbonamenti e callable reali invece di credenziali di produzione.
- **Promemoria prova OneSignal non annullabile**: `scheduleTrialReminder` (`functions/src/enrollment/notify.ts`) gira server-side ma schedula email e push con `send_after` al momento dell'iscrizione. Se l'utente si disiscrive, se il corso viene cancellato o spostato, o se `reminderEnabled` viene disattivato dopo, il messaggio parte comunque (il notification id non viene salvato). Ora che `sendDemoLessonWhatsappReminders` seleziona già i destinatari la sera prima, email e push possono spostarsi su quel cron con un invio immediato via `postToOneSignal`, senza `send_after`.
