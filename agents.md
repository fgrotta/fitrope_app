# FitRope Agent Guide

## Scopo del progetto

FitRope e una app Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Il backend applicativo e Firebase:

- `firebase_auth` per login, registrazione e verifica email
- `cloud_firestore` per utenti, corsi e stato iscrizioni
- `cloud_functions` per write-path server-side iscrizioni/abbonamenti e proxy sicuro verso OneSignal (email + push)
- Redux minimale per lo stato globale di sessione e lista corsi
- OneSignal: push native su Android/iOS + email server-side via Cloud Function. Push web disabilitate.

L'app e localizzata principalmente in italiano e il brand esposto in UI e `Fit House`, mentre il package resta `fitrope_app`.

## Stack e dipendenze chiave

| Componente | Dettaglio |
|---|---|
| Flutter SDK | `>=3.5.0-180.3.beta <4.0.0` |
| Flutter CI | `3.24.0` stable |
| Stato globale | `redux`, `redux_thunk`, `flutter_redux` |
| Backend | `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions` con callable in `europe-west8` |
| Notifiche | `onesignal_flutter` (mobile push) + Cloud Functions (email server-side). Web SDK disabilitato. |
| HTTP | `http` per comunicazione generica |
| Design system | `flutter_design_system` (Git dep da GitHub, branch main) |
| Localizzazione | `intl`, `flutter_localizations` (italiano primario) |
| Lint | `flutter_lints` v4.0.0 |
| Versione app | `1.1.2` |

Prima di modificare dipendenze o CI, verifica la compatibilita tra SDK dichiarato e versione usata nei workflow.

## Entry points

- App bootstrap: `lib/main.dart`
- Routing statico: `lib/router.dart`
- Store Redux: `lib/state/store.dart`
- Workflow protetto post-login: `lib/pages/protected/Protected.dart`

Sequenza di avvio in `main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
3. Se `--dart-define=USE_EMULATOR=true`, connessione agli emulatori Auth/Firestore/Functions (`europe-west8`) tramite `EMULATOR_HOST` (default `localhost`)
4. Se NON si usa l'emulatore, `OneSignalService.initialize(oneSignalAppId)`
5. `initializeDateFormatting('it_IT', null)`
6. `SafeArea` + `StoreProvider(store)` wrapping `MyApp`
7. `MaterialApp` con locale `it_IT`, route iniziale `INITIAL_ROUTE`

In modalita emulatore OneSignal non viene inizializzato, per evitare registrazioni su OneSignal produzione durante il QA locale.

## Mappa delle cartelle

```
lib/
├── main.dart                        # Bootstrap Firebase, emulatori, OneSignal, MaterialApp
├── router.dart                      # Route statiche + debug-only in kDebugMode
├── style.dart                       # Costanti di stile globali
├── firebase_options.dart            # Config Firebase per piattaforma
│
├── state/                           # Redux state management
│   ├── store.dart                   # Store con thunk middleware
│   ├── state.dart                   # AppState (user, isLoading, allCourses)
│   ├── actions.dart                 # 4 azioni Redux
│   └── reducers.dart                # Reducer puri
│
├── layout/                          # Sistema layout responsive
│   ├── breakpoints.dart             # Mobile/Tablet/Desktop/LargeDesktop
│   ├── breakpoint_builder.dart      # Widget responsive builder
│   └── app_shell.dart               # Scaffold principale (BottomNav vs NavigationRail)
│
├── pages/
│   ├── welcome/                     # Schermate pre-autenticazione
│   │   ├── SplashScreen.dart        # Splash iniziale, check auth
│   │   ├── WelcomePage.dart         # Landing page
│   │   ├── LoginPage.dart           # Login email/password
│   │   └── RegistrationPage.dart    # Registrazione nuovo utente
│   │
│   └── protected/                   # Area autenticata
│       ├── Protected.dart           # Scaffold principale con endDrawer admin
│       ├── HomePage.dart            # Dashboard con abbonamenti/certificati in scadenza
│       ├── CalendarPage.dart        # Calendario corsi con filtri e iscrizioni
│       ├── CourseManagementPage.dart # CRUD corsi (crea/modifica/duplica)
│       ├── RecurringCoursePage.dart  # Gestione corsi ricorrenti
│       ├── AdminUsersPage.dart      # Lista utenti admin
│       ├── CreateUserPage.dart      # Creazione utente (solo admin)
│       ├── UserDetailPage.dart      # Profilo/modifica utente (admin)
│       ├── AdminDashboardPage.dart  # Analytics (solo desktop)
│       └── DebugEmailPage.dart      # Invio email di test (solo kDebugMode)
│
├── api/                             # Layer Firestore
│   ├── getUserData.dart             # Fetch singolo utente
│   ├── authentication/              # CRUD e query utenti
│   │   ├── acceptRegolamento.dart   # Accettazione regolamento
│   │   ├── getUsers.dart            # Tutti gli utenti (cache 5 min)
│   │   ├── createUser.dart          # Creazione utente
│   │   ├── updateUser.dart          # Aggiornamento diff-based campi utente
│   │   ├── toggleUserStatus.dart    # Attiva/disattiva utente
│   │   ├── getUsersWithExpiringSubscriptions.dart
│   │   └── getUsersWithExpiringCertificates.dart
│   ├── courses/                     # CRUD corsi + thin wrapper callable enrollment
│   │   ├── getCourses.dart          # Tutti i corsi (cache 1 min)
│   │   ├── createCourse.dart
│   │   ├── updateCourse.dart
│   │   ├── deleteCourse.dart        # Callable admin atomica
│   │   ├── cleanCourses.dart        # Rimozione corsi vecchi
│   │   ├── enrollment_callable.dart # Helper condiviso per callable europe-west8
│   │   ├── joinWaitlist.dart        # Callable joinWaitlist
│   │   ├── leaveWaitlist.dart       # Callable leaveWaitlist
│   │   ├── recountCourseSubscribed.dart # Callable admin ricalcolo contatore
│   │   ├── subscribeToCourse.dart   # Callable subscribeToCourse
│   │   ├── unsubscribeToCourse.dart # Callable unsubscribeFromCourse
│   │   └── README_ISCRIZIONI.md     # Documentazione logica iscrizioni server-side
│   └── subscriptions/
│       └── assign_subscription.dart # Callable admin assignSubscription
│
├── authentication/                  # Flussi auth lato client
│   ├── login.dart                   # Login + OneSignal.login + addEmail
│   ├── registration.dart
│   ├── logout.dart                  # Logout + OneSignal.logout
│   ├── isLogged.dart
│   ├── deleteUser.dart
│   ├── resetPassword.dart
│   └── resendVerificationEmail.dart
│
├── services/                        # Servizi esterni e facade
│   ├── onesignal_service.dart       # Conditional export web/mobile
│   ├── onesignal_mobile.dart        # Wrapper onesignal_flutter
│   ├── onesignal_web.dart           # Disabilitato: metodi no-op
│   ├── notification_service.dart    # Proxy/debug email via Cloud Functions
│   └── email_templates.dart         # Template HTML email
│
├── types/                           # Modelli dati
│   ├── fitropeUser.dart             # FitropeUser + CancelledEnrollment + TipologiaIscrizione
│   ├── course.dart                  # Course
│   └── userSubscription.dart        # UserSubscription + enum famiglia/billing
│
├── components/                      # Widget riusabili
│   ├── active_subscription_card.dart
│   ├── assign_subscription_card.dart
│   ├── course_card.dart
│   ├── course_preview_card.dart
│   ├── course_unsubscribe_button.dart  # Bottone disiscrizione color-coded
│   ├── custom_text_field.dart
│   ├── loader.dart
│   └── sala_selector_card.dart
│
└── utils/                           # Helper e regole di dominio
    ├── course_unsubscribe_helper.dart  # Logica core disiscrizione
    ├── abbonamento_helper.dart         # Helper tipologie abbonamento
    ├── certificato_helper.dart         # Scadenza certificati
    ├── course_tags.dart                # Gestione tag corsi
    ├── course_types.dart               # Registry tipologie/famiglie/sale default
    ├── getCourseState.dart
    ├── getCourseTimeRange.dart
    ├── getTipologiaIscrizioneLabel.dart
    ├── formatDate.dart
    ├── randomId.dart
    ├── regolamento_helper.dart
    ├── sale.dart                       # Lista chiusa Sale
    ├── snackbar_utils.dart
    ├── subscription_labels.dart        # Label UI nuovo modello abbonamenti
    ├── subscription_plans.dart         # Catalogo piani Open/Hyrox/PT
    ├── refresh_manager.dart            # Logica refresh cache
    ├── user_cache_manager.dart         # Cache dati utente
    ├── user_display_utils.dart
    └── waitlist_ui_helper.dart
```

## Modelli dati

### FitropeUser (`lib/types/fitropeUser.dart`)

| Campo | Tipo | Descrizione |
|---|---|---|
| uid | String | ID univoco |
| email | String | Email utente |
| name, lastName | String | Nome e cognome |
| role | String | `Admin`, `Trainer`, `User` |
| courses | List\<String\> | Lista ID corsi iscritti |
| tipologiaIscrizione | TipologiaIscrizione? | Tipo abbonamento |
| entrateDisponibili | int? | Ingressi rimasti (pacchetto) |
| entrateSettimanali | int? | Limite ingressi settimanali |
| fineIscrizione | Timestamp? | Scadenza abbonamento |
| isActive | bool | Stato attivo/disattivo |
| isAnonymous | bool | Utente anonimo |
| createdAt | DateTime | Data creazione |
| certificatoScadenza | Timestamp? | Scadenza certificato medico |
| numeroTelefono | String? | Telefono |
| tipologiaCorsoTags | List\<String\> | Tag per filtrare accesso ai corsi |
| cancelledEnrollments | List\<CancelledEnrollment\> | Storico disiscrizioni |
| waitlistCourses | List\<String\> | Corsi in lista d'attesa (course IDs) |
| emailNotificationsEnabled | bool | Preferenza notifiche email (default true) |
| pushNotificationsEnabled | bool | Preferenza notifiche push (default true) |
| regolamentoAccettatoIl | Timestamp? | Accettazione regolamento |
| activeSubscriptions | List\<UserSubscription\> | Snapshot abbonamenti attivi (modello multi-abbonamento, read-path) |

### TipologiaIscrizione (enum)

- `PACCHETTO_ENTRATE` - Pacchetto a ingressi
- `ABBONAMENTO_MENSILE` - Mensile
- `ABBONAMENTO_TRIMESTRALE` - Trimestrale
- `ABBONAMENTO_SEMESTRALE` - Semestrale
- `ABBONAMENTO_ANNUALE` - Annuale
- `ABBONAMENTO_PROVA` - Prova

### CancelledEnrollment (nested in FitropeUser)

Traccia le disiscrizioni con: `courseId`, `cancelledAt`, `entryLost` (se l'ingresso e stato perso), `courseStartDate`.

### Modello multi-abbonamento

Un utente puo avere piu abbonamenti attivi insieme. La fonte di verita e la collezione `subscriptions`; lo snapshot `FitropeUser.activeSubscriptions` (lista di `UserSubscription`) alimenta il calcolo client di `getCourseState` e viene scritto dalle Cloud Functions. Se `activeSubscriptions` non contiene voci vive, `getCourseState` usa il modello legacy (`tipologiaIscrizione`/`entrate*`/`fineIscrizione`).

- **UserSubscription** (`lib/types/userSubscription.dart`): `id?`, `planKey`, `family` (`SubscriptionFamily`: OPEN/HYROX/PT), `billingMode` (`BillingMode`: FREQUENCY/ENTRIES), `courseTypeTags` (accesso), `weeklyFrequency` (2/3/`null`=illimitato), `remainingEntries`, `startDate`, `endDate`.
- **Catalogo** (`lib/utils/subscription_plans.dart`): Open {2x, 3x, illimitato} x {1,3,6,12} = 12; Hyrox e PT 10 ingressi x {1,3,6,12}.
- **getCourseState (scope per famiglia):** gli abbonamenti che coprono la tipologia (tag) del corso ne determinano l'idoneita — FREQUENCY conta i corsi della stessa tipologia nella settimana (`null`=illimitato), ENTRIES verifica `remainingEntries > 0`; scadenza per-abbonamento. Accesso = tag legacy OPPURE copertura abbonamento; i corsi accessibili solo via tag (es. Hey Mamma) non hanno limiti di abbonamento.
- **Caveat modello misto:** se esiste almeno una voce viva nello snapshot, il modello multi-abbonamento vince sul fallback legacy in modo globale. I crediti legacy residui non vengono usati come fallback per famiglie non coperte; in fase gestionale conviene convertire/azzerare il residuo legacy quando si assegna un nuovo abbonamento.

### Course (`lib/types/course.dart`)

| Campo | Tipo | Descrizione |
|---|---|---|
| uid | String | ID univoco (campo `id` deprecato) |
| name | String | Nome corso |
| startDate, endDate | Timestamp | Orario inizio e fine |
| capacity | int | Posti disponibili |
| subscribed | int | Iscritti attuali |
| trainerId | String? | Trainer assegnato |
| tags | List\<String\> | Tag per filtro accesso |
| waitlist | List\<String\> | Utenti in lista d'attesa (user IDs) |
| reminderEnabled | bool | Se true invia promemoria (default true) |
| waitlistEnabled | bool | Se true la lista d'attesa è attiva (default true) |
| sala | String? | Sala del corso (lista chiusa `Sale`: "Sala 1"/"Sala 2"; null = legacy/non impostata) |

I tag dei corsi sono in `CourseTags` (Personal Trainer, Open, **Hyrox**, Hey Mamma). Il registry `CourseTypes` (`lib/utils/course_types.dart`) mappa ogni tag a una tipologia con `displayName` e `defaultSala` (quest'ultimo previsto per il futuro, non usato in v1). La tipologia di un corso si deriva dai `tags` via `CourseTypes.primaryForTags`.

## Stato globale Redux

`AppState` (`lib/state/state.dart`) contiene solo:

- `user` (FitropeUser?) - utente autenticato corrente
- `isLoading` (bool) - flag loading globale
- `allCourses` (List\<Course\>) - tutti i corsi disponibili

Azioni (`lib/state/actions.dart`):

- `SetUserAction(user)` - imposta utente corrente
- `StartLoadingAction()` / `FinishLoadingAction()` - toggle loading
- `SetAllCoursesAction(courses)` - aggiorna lista corsi

Store creato con `thunkMiddleware` per operazioni asincrone.

## Layout responsive

Breakpoint definiti in `lib/layout/breakpoints.dart`:

| Tipo | Larghezza |
|---|---|
| Mobile | < 600px |
| Tablet | 600-899px |
| Desktop | 900-1599px |
| Large Desktop | >= 1600px |

`AppShell` (`lib/layout/app_shell.dart`) switcha automaticamente tra:

- **Mobile/Tablet**: `BottomNavigationBar` con 2-3 tab (Home, Calendario, Utenti se admin)
- **Desktop**: `NavigationRail` laterale con iniziali utente e pulsante logout

Usa sempre `isDesktop(context)` o `breakpointOf(context)` per decisioni di layout. La `AdminDashboardPage` e disponibile solo su desktop.

## Flusso autenticazione

1. `SplashScreen` controlla `isLogged()` via `FirebaseAuth.currentUser`
2. Se loggato: naviga a `Protected` → carica dati utente → dashboard per ruolo
3. Se non loggato: naviga a `WelcomePage` → `LoginPage` o `RegistrationPage`
4. **Registrazione**: crea utente Firebase Auth + documento Firestore con `ABBONAMENTO_PROVA` (30 giorni)
5. **Login**: verifica email/password, controlla email verificata, controlla `isActive == true`, carica documento utente, aggiorna Redux
6. **Logout**: sign out Firebase Auth, reset Redux state

## Routing (`lib/router.dart`)

| Costante | Path | Pagina |
|---|---|---|
| `SPLASH_ROUTE` | `/splash` | SplashScreen |
| `WELCOME_ROUTE` | `/` | WelcomePage |
| `LOGIN_ROUTE` | `/login` | LoginPage |
| `REGISTRATION_ROUTE` | `/registration` | RegistrationPage |
| `PROTECTED_ROUTE` | `/protected` | Protected |
| `COURSE_MANAGEMENT_ROUTE` | `/course-management` | CourseManagementPage |
| `RECURRING_COURSE_ROUTE` | `/recurring-course` | RecurringCoursePage |
| `DEBUG_EMAIL_ROUTE` | `/debug-email` | DebugEmailPage _(solo `kDebugMode`)_ |

`CourseManagementPage` accetta argomenti: `courseToEdit`, `courseToDuplicate`, `mode`.

## Regole di business

La parte piu delicata del progetto e la logica di iscrizione ai corsi.

Da PR4/PR5 le scritture del dominio iscrizioni sono server-side: il client mantiene le firme pubbliche in `lib/api/courses/`, ma i file Dart sono thin wrapper verso callable Cloud Functions in `europe-west8`. La logica autoritativa sta in `functions/src/enrollment/` (`eligibility.ts`, `refund.ts`, `subscription.ts`, `enrollment.ts`, `admin.ts`).

### Iscrizione

- `subscribeToCourse`: callable transazionale che verifica auth, ruolo, corso non iniziato, capienza, accesso tag/abbonamento, scadenze, crediti e limiti settimanali.
- **Legacy pacchetto/prova**: decrementa `entrateDisponibili` solo per modelli a ingressi.
- **Multi-abbonamento ENTRIES**: decrementa `remainingEntries` e aggiorna snapshot `activeSubscriptions`.
- **Multi-abbonamento FREQUENCY**: non decrementa crediti, ma applica limite settimanale per tipologia/famiglia.
- Ogni prenotazione registra il consumo reale in `users.{uid}.enrollmentConsumption`, usato per rimborsare la fonte corretta.

### Disiscrizione

- `unsubscribeFromCourse`: callable transazionale invocata dai wrapper `unsubscribeToCourse` / `forceUnsubscribeWithNoRefund`.
- **Legacy pacchetto/prova e multi-abbonamento ENTRIES**: rimborso oltre 8 ore; entro 8 ore serve conferma e l'ingresso e perso.
- **Multi-abbonamento FREQUENCY / abbonamenti temporali legacy**: oltre 4 ore libera solo il posto; entro 4 ore serve conferma e viene registrato `cancelledEnrollments.entryLost`, che conta nel limite settimanale.
- **Admin/Trainer su altri utenti**: il server riconosce actor diverso da target e rimborsa sempre, ignorando `confirmedNoRefund`.
- **deleteCourse admin**: callable atomica; corsi futuri rimborsano, corsi gia iniziati sono pulizia storico e non rimborsano.

### Restrizioni ruolo

- Admin e Trainer non dovrebbero iscriversi ai corsi come utenti normali
- I flussi admin distruttivi (`deleteCourse`, `recountCourseSubscribed`) sono Admin-only lato server.

### Waitlist

- `joinWaitlist` / `leaveWaitlist` sono callable server-side.
- `waitlistEnabled == false` fa tornare `FULL` nel client e fa rifiutare `joinWaitlist` sul server.
- Punto aperto di review: `joinWaitlistHandler` valida corso pieno, duplicati, waitlist flag e corso iniziato, ma non replica ancora tutta l'eligibility server-side di `subscribeToCourse` (tag, crediti, limiti, scadenze).

### Cache

- Corsi: cache 1 minuto (`getCourses`)
- Utenti: cache 5 minuti (`getUsers`)
- Dopo operazioni su corsi o utenti, il codice invalida/aggiorna cache e store

Riferimenti:

- `lib/utils/course_unsubscribe_helper.dart`
- `lib/api/courses/README_ISCRIZIONI.md`
- `lib/api/courses/subscribeToCourse.dart`
- `lib/api/courses/unsubscribeToCourse.dart`
- `lib/api/courses/enrollment_callable.dart`
- `functions/src/enrollment/`

Se tocchi queste aree, aggiorna o aggiungi test in `test/` e `functions/src/__tests__/`; se tocchi rules o transazioni reali, aggiorna anche `functions/src/__integration__/`.

## Firebase

- **Progetto**: `fit-rope-app-1f575`
- **Auth domain**: `fit-rope-app-1f575.firebaseapp.com`
- **Piattaforme**: Web, Android, iOS, macOS, Windows
- **Config**: `lib/firebase_options.dart` (auto-generato da FlutterFire CLI)
- **Piano**: Blaze (richiesto per Cloud Functions)

### Collezioni Firestore

- `users` - documenti utente con dati abbonamento, iscrizioni, waitlist, preferenze notifiche
- `courses` - documenti corso con orario, capacita e waitlist
- `subscriptions` - fonte di verita dei nuovi abbonamenti multi-famiglia; scrittura solo server

### Pattern

- Transazioni Admin SDK nelle Cloud Functions per iscrizione/disiscrizione/waitlist, assegnazione abbonamenti, cancellazione corso e recount
- Server timestamp per audit trail
- Invalidazione cache dopo mutazioni
- `firestore.rules` blocca le scritture client sui campi server-owned: `courses`, `waitlistCourses`, `activeSubscriptions`, `enrollmentConsumption`, `cancelledEnrollments`, `subscribed`, `waitlist`, e sulla collezione `subscriptions`
- CRUD corso resta parzialmente client-side per create/update, ma senza scrivere `subscribed`/`waitlist`; `deleteCourse` passa solo da callable
- Ordine deploy sicuro: `firebase deploy --only functions`, poi pubblicazione web/app nuova, infine `firebase deploy --only firestore:rules`

### Ambiente locale emulatori

- Avvio app contro emulatori: `flutter run -d chrome --dart-define=USE_EMULATOR=true`
- Da device fisico: aggiungi `--dart-define=EMULATOR_HOST=<IP Mac>`
- Emulator Suite richiede Java 21+ con firebase-tools 15.x
- Seed dati sintetici: `cd functions && npm run seed:emulator`
- Non usare dati reali o OneSignal produzione durante il QA locale

## Notifiche (OneSignal + Cloud Functions)

### Architettura

```
Flutter (web + mobile)
    │ httpsCallable('sendOneSignalNotification')
    ▼
Cloud Function (functions/src/handler.ts)
    │ REST API key da Google Secret Manager
    ▼
OneSignal REST API (push + email)
```

La REST API key **non e mai esposta al client**. Il client chiama la Cloud Function, che verifica l'auth Firebase, inietta `app_id` server-side e inoltra a OneSignal.

### Casi d'uso

| Trigger | Dove (da PR4/PR5: SERVER-side) | Invio |
|---|---|---|
| Disiscrizione da corso pieno | Cloud Function `unsubscribeFromCourse` → `functions/src/enrollment/notify.ts:notifyWaitlistUsers` | Immediato — email a tutti gli utenti in waitlist (utenti nuovo modello mai rimossi per `fineIscrizione` stantio) |
| Iscrizione utente `ABBONAMENTO_PROVA` (solo modello legacy) | Cloud Function `subscribeToCourse` → `functions/src/enrollment/notify.ts:scheduleTrialReminder` | Schedulato — sera prima alle 19:00 Europe/Rome |
| Debug manuale (solo `kDebugMode`) | `lib/services/notification_service.dart:sendTestWaitlistEmail` / `sendTestTrialReminderEmail` | Immediato — inviato all'utente corrente via FAB in `Protected` → `DebugEmailPage` |

Le versioni client di `notifyWaitlistUsers`/`scheduleTrialReminder` sono state RIMOSSE (PR4/PR5): il server è l'unica autorità.

**Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).

### SDK client

- **Mobile** (`lib/services/onesignal_mobile.dart`): wrapper di `onesignal_flutter` con `requestPermission` — push native attive
- **Web** (`lib/services/onesignal_web.dart`): **disabilitato**, tutti i metodi sono no-op. Il caricamento del Web SDK in `web/index.html` è commentato.
- **Facade** (`lib/services/onesignal_service.dart`): `export ... if (dart.library.html)` per scelta automatica

Su web le email passano via Cloud Function (`ensureOneSignalUser` crea l'utente server-side, poi `sendOneSignalNotification` invia). Il service worker `web/OneSignalSDKWorker.js` rimane nel progetto ma non viene mai caricato finché il blocco script in `web/index.html` è commentato.

### Flag per corso

Ogni `Course` ha due flag configurabili dall'admin in creazione/duplicazione:

- `reminderEnabled` (default true): se false, `scheduleTrialReminder` (server) salta l'invio per questo corso
- `waitlistEnabled` (default true): se false, `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`, `joinWaitlist` (server) rifiuta e `notifyWaitlistUsers` (server) salta l'invio

Entrambi si applicano anche ai corsi creati tramite `RecurringCoursePage`.

### Cloud Function

- Source: `functions/src/`
- Build: TypeScript → `functions/lib/`
- Test: Jest in `functions/src/__tests__/`
- Secret: `firebase functions:secrets:set ONESIGNAL_REST_API_KEY`
- Deploy: `firebase deploy --only functions`

### Preferenze utente

Ogni utente ha in Firestore `emailNotificationsEnabled` e `pushNotificationsEnabled` (default `true`). I trigger principali waitlist/trial reminder sono server-side in `functions/src/enrollment/notify.ts`; `notification_service.dart` resta per helper/proxy callable e invii manuali di debug.

## Dashboard Admin

`lib/pages/protected/AdminDashboardPage.dart` contiene:

- `AdminDashboardPage`: sezioni analisi utenti, corsi (ultimi 6 mesi) e abbonamenti con grafici a barre
- `UserListDrawer`: drawer laterale con lista utenti ricercabile (nome, email, telefono), aperto dalla dashboard o dall'area admin

La dashboard e visibile solo su desktop (`isDesktop(context)`). Il `Scaffold` in `Protected.dart` gestisce l'`endDrawer` con la chiave globale `_scaffoldKey`.

## Testing

### Flutter (test/)

Test focalizzati su logica iscrizioni, serializzazione modelli, sale, course types, subscription plans/labels, update diff-based e waitlist. Suite principali:

- `active_subscriptions_state_test.dart`, `userSubscription_test.dart`, `subscription_plans_test.dart`, `subscription_labels_test.dart`
- `course_unsubscribe_test.dart`, `enrollment_new_logic_test.dart`, `enrollment_current_logic_test.dart`, `subscribe_restriction_test.dart`
- `waitlist_state_test.dart`, `waitlist_operations_test.dart`, `course_flags_test.dart`
- `createCourse_test.dart`, `updateCourse_test.dart`, `updateUser_test.dart`
- `course_sala_serialization_test.dart`, `sale_test.dart`, `course_types_test.dart`
- `notification_preferences_test.dart`, `email_templates_test.dart`

Framework: `flutter_test` con `group()` e `setUp()`. Conteggio verificato localmente: `flutter test` passa 265 test.

### Cloud Functions (functions/src/__tests__/)

Test Jest su handler OneSignal e dominio enrollment:

- `handler.test.ts` - auth, validazione payload, inoltro a OneSignal, errori
- `eligibility.test.ts`, `refund.test.ts`, `courseTypes.test.ts`, `enrollment.test.ts`
- `enrollmentHandlers.test.ts`, `adminHandlers.test.ts`, `assignSubscription.test.ts`
- `notify.test.ts`, `notifyOrchestration.test.ts`, `conventions.test.ts`

Framework: `jest` + `ts-jest`. Conteggio verificato localmente: `cd functions && npm test` passa 210 test.

### Integration tests emulatori

I test in `functions/src/__integration__/` girano su Firebase Emulator Suite:

- `enrollment.integration.test.ts` - callable reali, transazioni, concorrenza, authz
- `firestoreRules.integration.test.ts` - lockdown field-level e payload reali con `@firebase/rules-unit-testing`

Esegui con `cd functions && npm run test:integration`. Richiede Java 21+ e firebase-tools 15.x; in CI viene configurato da `.github/workflows/ci.yml`.

## CI/CD

### GitHub Actions

**ci.yml** (branch `main`, `develop`):

- `test`: `flutter pub get` -> `flutter test` -> `flutter analyze` -> `flutter format --set-exit-if-changed .` -> `flutter build web --debug`
- `functions-test`: Node 20, `npm ci`, `npm run build`, `npm test`
- `functions-integration`: Node 20 + Java 21 + firebase-tools 15, `npm run test:integration` con project `demo-fitrope`

Nota operativa: `flutter analyze` e parte della CI. Se resta rosso anche solo con issue info-level, il job fallisce.

**release.yml** (branch `release`):

- Test completi + build web release
- Creazione automatica GitHub Release
- Deploy su GitHub Pages via branch `gh-pages`

**URL produzione**: https://dellarosamarco.github.io/fitrope_app/

### Dependabot

- Aggiornamenti settimanali (lunedi ore 9:00 UTC)
- Traccia dipendenze pub e github-actions
- Assegnato a `dellarosamarco`

## Comandi utili

### Flutter

```bash
flutter pub get
flutter test
flutter analyze
flutter format --set-exit-if-changed .
flutter build web --debug
flutter run -d chrome
```

### Cloud Functions

```bash
# Sviluppo locale
cd functions
npm install            # installa dipendenze Node (runtime Node 20)
npm run build          # compila TypeScript
npm test               # esegue test Jest unitari (210 test verificati)
npm run test:integration # Emulator Suite, richiede Java 21+
npm run seed:emulator  # seed dati sintetici su emulatori avviati
npm run serve          # avvia emulatore Firebase Functions

# Deploy
firebase deploy --only functions                        # deploy in produzione
firebase functions:secrets:set ONESIGNAL_REST_API_KEY   # setup/aggiorna secret
firebase functions:log --only sendOneSignalNotification # vedi log runtime
firebase functions:delete sendOneSignalNotification     # elimina la function
```

Il predeploy in `firebase.json` compila TypeScript automaticamente via `./node_modules/.bin/tsc` (invocazione diretta senza npm per evitare il bug stdin di npm 10+).

**Setup iniziale** (una volta sola per ambiente):

1. `firebase login`
2. `firebase functions:secrets:set ONESIGNAL_REST_API_KEY` (incolla la REST API Key OneSignal)
3. `firebase deploy --only functions`

Se il primo deploy fallisce per permessi IAM (errore "missing permission on the build service account"), assegna al compute service account (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`) i ruoli:

- `roles/cloudbuild.builds.builder`
- `roles/artifactregistry.writer`
- `roles/logging.logWriter`

**Workflow aggiornamento function:**

1. Modifica `functions/src/`
2. `cd functions && npm run build && npm test` (verifica locale)
3. Commit
4. `firebase deploy --only functions`

Quando cambi il secret, serve sempre un re-deploy per bindare il nuovo valore al runtime.

**Workflow deploy blocco enrollment/rules:**

1. `firebase deploy --only functions`
2. Pubblica la nuova build web/app
3. `firebase deploy --only firestore:rules` per ultime, dopo che il nuovo client usa le callable

## Punti aperti di review

- `functions/src/enrollment/enrollment.ts:joinWaitlistHandler` non replica ancora tutta l'eligibility server-side di `subscribeToCourse` (tag, crediti, limiti settimanali, scadenze).
- `firestore.rules` in create corso vincola `request.resource.data.id == courseId`, ma dovrebbe vincolare anche `uid == courseId` per evitare corsi ambigui rispetto alle query Functions su `uid`.
- Il bottone UI "Correggi conteggio" puo comparire anche ai Trainer tramite `CoursePreviewCard`, ma `recountCourseSubscribed` e Admin-only lato server.
- `assignSubscriptionHandler` dovrebbe leggere e validare l'esistenza del doc utente target prima di creare `subscriptions` e fare `tx.set(userRef, ..., merge: true)`.
- `flutter analyze` oggi non e pulito localmente: fallisce con issue info-level. Finche la CI esegue analyze senza override, questo resta un rischio merge.

## Osservazioni operative

- Se rinomini file o classi, ricontrolla sempre la compatibilita con filesystem case-sensitive (es. `HomePage.dart` non `Homepage.dart`).
- Il codice usa ancora molti `print` e side effect diretti nei widget; prima di grandi refactor, separa i cambiamenti di dominio da quelli UI.
- Non usare path assoluti nei file di documentazione: usa sempre path relativi alla root del progetto.
- Nessun sistema di code generation (build_runner, freezed, json_serializable): la serializzazione e manuale con `toJson()`/`fromJson()`.
- Nessuna separazione ambienti (dev/staging/prod): un unico progetto Firebase.
- Localizzazione hardcoded in italiano, nessun file .arb: le stringhe UI sono direttamente nel codice.
- Nelle Cloud Functions importa `Timestamp` e `FieldValue` da `firebase-admin/firestore`, non da `admin.firestore.*`, per compatibilita con runtime emulato.

## Dove intervenire in base al task

| Area | File principali |
|---|---|
| Login, logout, verifica email, reset password | `lib/authentication/`, `lib/pages/welcome/` |
| Sessione e loading overlay | `lib/state/`, `lib/pages/protected/Protected.dart` |
| Gestione utenti admin | `lib/pages/protected/AdminUsersPage.dart`, `CreateUserPage.dart`, `UserDetailPage.dart`, `lib/api/authentication/` |
| Gestione corsi | `lib/pages/protected/CourseManagementPage.dart`, `RecurringCoursePage.dart`, `lib/api/courses/` |
| Regole iscrizione/disiscrizione | `functions/src/enrollment/`, `lib/api/courses/`, `lib/utils/getCourseState.dart`, `lib/utils/course_unsubscribe_helper.dart`, `test/` |
| Waitlist corsi | `lib/api/courses/joinWaitlist.dart`, `leaveWaitlist.dart`, `lib/utils/waitlist_ui_helper.dart` |
| Abbonamenti multi-famiglia | `lib/types/userSubscription.dart`, `lib/utils/subscription_plans.dart`, `lib/utils/subscription_labels.dart`, `lib/api/subscriptions/`, `functions/src/enrollment/subscription.ts` |
| Sale e tipologie corso | `lib/utils/sale.dart`, `lib/utils/course_types.dart`, `lib/utils/course_tags.dart`, `lib/components/sala_selector_card.dart` |
| Firestore rules e emulatori | `firestore.rules`, `firebase.json`, `docs/AMBIENTI_DI_TEST.md`, `functions/src/__integration__/` |
| Notifiche push/email | `lib/services/notification_service.dart`, `lib/services/email_templates.dart`, `functions/src/` |
| Test email manuale (debug) | `lib/pages/protected/DebugEmailPage.dart`, `lib/services/notification_service.dart` (`sendTestWaitlistEmail`, `sendTestTrialReminderEmail`) |
| OneSignal SDK | `lib/services/onesignal_*.dart`, `web/index.html` (web SDK commentato), `web/OneSignalSDKWorker.js` |
| Dashboard e analisi | `lib/pages/protected/AdminDashboardPage.dart` |
| Layout e breakpoints | `lib/layout/` |
| Stili globali | `lib/style.dart`, `lib/components/` |

## Regole per gli agenti

- Parti sempre dai file reali, non dal `README.md`.
- Se modifichi logica di iscrizione, allinea client display (`getCourseState.dart` / `course_unsubscribe_helper.dart`) e server enforcement (`functions/src/enrollment/`).
- Il client non deve scrivere direttamente campi enrollment server-owned (`courses`, `waitlistCourses`, `activeSubscriptions`, `enrollmentConsumption`, `cancelledEnrollments`, `subscribed`, `waitlist`): usa le callable/wrapper esistenti.
- Se modifichi logica Flutter di corsi/abbonamenti, esegui almeno `flutter test`; se modifichi Functions, esegui `cd functions && npm run build && npm test`.
- Se tocchi `firestore.rules`, emulatori o transazioni reali, esegui anche `cd functions && npm run test:integration` con Java 21.
- Se tocchi import o rename file, controlla la compatibilita con filesystem case-sensitive.
- Mantieni la UI in italiano salvo requisito esplicito diverso.
- Quando aggiungi campi ai modelli Firestore, aggiorna sia `toJson` sia `fromJson`.
- Dopo operazioni su corsi o utenti, assicurati di invalidare/aggiornare cache e Redux store.
- Usa transazioni Admin SDK lato Functions per qualsiasi nuova operazione che modifica contemporaneamente utente e corso.
- Non mettere mai la REST API key di OneSignal (o altre secret) nel codice Flutter: devono stare in Google Secret Manager, accessibili solo dalle Cloud Functions.
- Se aggiungi nuovi tipi di notifica, aggiorna `functions/src/enrollment/notify.ts`, `notification_service.dart` solo se serve un proxy/debug client, e i template in `email_templates.dart`/`emailTemplates.ts`. Il payload OneSignal non deve contenere `app_id` (iniettato server-side).
