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
npm ci                   # installazione riproducibile (runtime Functions Node 22)
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

# Staging manuale: configurare prima functions/.env.fit-rope-staging
firebase deploy --project staging --only functions
STAGING_PROJECT_ID=fit-rope-staging npm run seed:staging

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

## Verifica live e lezioni operative

> **Policy — salva cosa impari.** Al termine di ogni sviluppo significativo, registra le lezioni apprese (trappole dell'ambiente, errori da non ripetere, pattern utili): se hanno valore generale per il progetto aggiungile a questa sezione; in ogni caso annotale nella memoria di progetto. Così le scoperte non vanno riscoperte alla sessione successiva.

Lezioni dal lavoro di sviluppo UI (verifica delle modifiche nel browser):

- `flutter run -d web-server` **ricompila solo all'avvio o su hot-restart** (`R` da stdin). Un'istanza lanciata in background non riceve `R`: dopo ogni modifica al codice **riavvia il run** (kill della porta + relaunch), non basta ricaricare la pagina.
- Il browser serve un `main.dart.js` cache-ato: dopo il relaunch fai un **hard reload** (Cmd/Ctrl+Shift+R), altrimenti vedi il build vecchio (sintomo tipico: il default sembra sbagliato o "la modifica non ha effetto").
- Per testare i **breakpoint responsive** verifica la larghezza reale (`window.innerWidth`): il ridimensionamento della finestra può essere inaffidabile. Breakpoint in `lib/layout/breakpoints.dart` (mobile <600, tablet <900, desktop <1600, largeDesktop ≥1600).
- **Pre-commit hook**: non bypassarlo come procedura ordinaria. Se l'ambiente restituisce erroneamente SDK `0.0.0-unknown`, esegui prima manualmente gli stessi gate (`flutter test`, `flutter analyze --no-fatal-infos`, formattazione e, quando applicabile, test Functions), poi documenta il problema dell'ambiente nel commit o nella PR.

### Deploy web / aggiornamento PWA (cache stantia su iOS)

- Produzione: `https://app.fithousemonza.it`, hosting Hostinger/LiteSpeed, deploy **manuale** (`flutter build web --wasm --release` -> upload di `build/web`).
- Staging: GitHub Pages del repository canonico, pubblicato automaticamente da `develop` tramite `.github/workflows/staging.yml`; non sostituisce il deploy Hostinger. La build usa `APP_ENV=staging` e Firebase separato. `web/.htaccess` viene copiato automaticamente in `build/web/` dal build Flutter: è il modo per far applicare regole di cache a Hostinger senza toccare il pannello.
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
- Nomi file Dart: rispetta il case esatto (es. `HomePage.dart`, non `homepage.dart`).
- Stato globale Redux minimale: non aggiungere campi a `AppState` senza necessita reale.
- Dopo mutazioni su corsi/utenti, invalida la cache (`refresh_manager`, `user_cache_manager`).
- Per iscrizioni, disiscrizioni, waitlist, assegnazione abbonamenti, delete e recount usa le callable in `europe-west8`: le transazioni autoritative sono nelle Cloud Functions. Le scritture client dirette restano limitate al CRUD corso consentito dalle rules.
- **Pull request**: apri sempre le PR nel fork `fgrotta/fitrope_app` con base `main`, mai verso l'upstream `dellarosamarco/fitrope_app`. Questo repo è un fork, quindi `gh pr create` di default punterebbe al parent: usa `gh pr create --repo fgrotta/fitrope_app --base main`.

## Aree sensibili

La logica di iscrizione/disiscrizione ai corsi e la parte piu critica. Se la modifichi:

1. Leggi `lib/api/courses/README_ISCRIZIONI.md`
2. Esegui i test: `flutter test`
3. File chiave: `lib/api/courses/subscribe_to_course.dart`, `unsubscribeToCourse.dart`, `lib/utils/course_unsubscribe_helper.dart`

### Notifiche OneSignal

- In staging (`APP_ENV=staging`) la Function invia email solo a UID `stg_` con email nella allowlist `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`; i payload push e tutti gli altri destinatari sono soppressi.

- REST API key **non** nel codice Flutter: sta in Google Secret Manager, usata solo dalla Cloud Function.
- Se modifichi il payload inviato a OneSignal, non includere `app_id` — lo inietta la function server-side.
- `notification_service.dart` chiama `FirebaseFunctions.instance.httpsCallable('sendOneSignalNotification')`.
- Su web le chiamate dirette a OneSignal falliscono per CORS: passa sempre dalla Cloud Function.
- **Push web disabilitate**: il Web SDK OneSignal è commentato in `web/index.html` e `onesignal_web.dart` è no-op. Le email su web passano via Cloud Function `sendOneSignalNotification`, che garantisce da sola i destinatari su OneSignal (vedi punto "Alias OneSignal" sotto); `ensureOneSignalUser` resta chiamata al login. Le push native restano attive su Android/iOS via `onesignal_flutter`.
- Ogni corso ha i flag `reminderEnabled` e `waitlistEnabled`: se false, `scheduleTrialReminder` / `notifyWaitlistUsers` saltano l'invio e `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`.
- **Alias OneSignal prima dell'invio**: `include_aliases: {external_id: [...]}` fallisce silenziosamente (200 OK, `recipients: 0`, nessun errore) se l'utente non ha mai fatto login — l'alias viene creato solo al login self-service (caso tipico: utente creato da Admin/walk-in e mai loggato). La garanzia è **server-side** in `sendOneSignalNotificationHandler` (`functions/src/handler.ts`): per ogni invio con `target_channel: 'email'` + `include_aliases.external_id`, la function legge l'email da Firestore (`users/{uid}`) e chiama `ensureOneSignalEmailSubscription` (idempotente) prima della POST. I call-site client NON devono più fare l'ensure prima degli invii; resta solo al login. `postToOneSignal` logga warning su 200-con-errors e `recipients: 0` (visibili con `firebase functions:log --only sendOneSignalNotification`). Nota: l'ensure riabilita anche una subscription email disattivata dal link di unsubscribe OneSignal — il filtro reale sono i flag `emailNotificationsEnabled`/`pushNotificationsEnabled` su Firestore. Gli invii server-side diretti via `postToOneSignal` (es. cron certificati) devono invece chiamare l'ensure esplicitamente, come fa `runCertificateEmails`.
- **Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).
- **Debug email**: in `kDebugMode` è disponibile un FAB in `Protected` che apre `DebugEmailPage` (`/debug-email`). Permette di inviare email di test (waitlist e promemoria prova) all'utente corrente senza triggering reale degli eventi. Le funzioni `sendTestWaitlistEmail` / `sendTestTrialReminderEmail` sono in `notification_service.dart`.

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

- **Tipologia corso: doppio binario `tags` + `courseType`**: il modello `Course` mantiene sia `tags` (fonte per eligibility e supporto a Hyrox/Hey Mamma) sia `courseType` (enum legacy `open` / `personal_trainer`, usato anche dalle immagini). Definire una migrazione esplicita prima di rimuovere uno dei due campi; non trattare `CourseType.label` come deprecato finche non esiste un sostituto completo.
- **Test E2E da riallineare al nuovo modello** (`integration_test/`, attualmente in `skip: true`):
  - `helpers/seed.dart` crea documenti direttamente e valorizza solo i `tags`; definire un seed compatibile con il modello misto e con la policy di eligibility corrente.
  - Rivalidare `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` contro Emulator Suite, con abbonamenti e callable reali invece di credenziali di produzione.
