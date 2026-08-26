# FitRope Agent Guide

## Scopo del progetto

FitRope e una app Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Il backend applicativo e Firebase:

- `firebase_auth` per login, registrazione e verifica email
- `cloud_firestore` per utenti, corsi e stato iscrizioni
- `cloud_functions` per write-path server-side iscrizioni/abbonamenti e proxy sicuro verso OneSignal (email + push)
- Redux minimale per lo stato globale di sessione e lista corsi
- OneSignal: push native su Android/iOS + Web SDK v16 attivo su web (push opt-in e email) + email applicative server-side via Cloud Function.

L'app e localizzata principalmente in italiano e il brand esposto in UI e `Fit House`, mentre il package resta `fitrope_app`.

## Stack e dipendenze chiave

| Componente | Dettaglio |
|---|---|
| Flutter SDK | `>=3.5.0-180.3.beta <4.0.0` |
| Flutter CI | `3.41.6` stable |
| Stato globale | `redux`, `redux_thunk`, `flutter_redux` |
| Backend | `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions` con callable in `europe-west8` |
| Notifiche | `onesignal_flutter` (mobile push) + Web SDK v16 via bridge JS (`web/index.html` + `onesignal_web.dart`) + Cloud Functions (email server-side) |
| Design system | `flutter_design_system` (Git dep da GitHub, branch main) |
| Localizzazione | `intl`, `flutter_localizations` (italiano primario) |
| Lint | `flutter_lints` v4.0.0 |
| Versione app | `1.3.0` |

Prima di modificare dipendenze o CI, verifica la compatibilita tra SDK dichiarato e versione usata nei workflow.

## Entry points

- App bootstrap: `lib/main.dart`
- Routing statico: `lib/router.dart`
- Store Redux: `lib/state/store.dart`
- Workflow protetto post-login: `lib/pages/protected/protected.dart`

Sequenza di avvio in `main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Firebase.initializeApp` seleziona `DefaultFirebaseOptions` produzione o `StagingFirebaseOptions` con `--dart-define=APP_ENV=staging`
3. Se `--dart-define=USE_EMULATOR=true`, connessione agli emulatori Auth/Firestore/Functions (`europe-west8`) tramite `EMULATOR_HOST` (default `localhost`)
4. Se NON si usa l'emulatore, `OneSignalService.initialize(oneSignalAppId)`
5. `initializeDateFormatting('it_IT', null)` + `initItalianTime()` (database timezone Europe/Rome)
6. `SafeArea` + `StoreProvider(store)` wrapping `MyApp`
7. `MaterialApp` con locale `it_IT`, route iniziale `INITIAL_ROUTE`; su build staging il builder aggiunge un `Banner` "STAGING" 

In modalita emulatore OneSignal non viene inizializzato, per evitare registrazioni su OneSignal produzione durante il QA locale.

## Mappa delle cartelle

```
lib/
├── main.dart                              # Bootstrap Firebase, emulatori, OneSignal, MaterialApp
├── router.dart                            # Route statiche + debug-only in kDebugMode
├── style.dart                             # Costanti di stile globali
├── firebase_options.dart                  # Config Firebase produzione
├── firebase_options_staging.dart          # Config Firebase staging da dart-define
├── app_environment.dart                   # Selezione ambiente prod/staging
│
├── state/                                 # Redux state management
│   ├── store.dart                         # Store con thunk middleware
│   ├── state.dart                         # AppState (user, isLoading, allCourses)
│   ├── actions.dart                       # 4 azioni Redux
│   └── reducers.dart                      # Reducer puri
│
├── layout/                                # Sistema layout responsive
│   ├── breakpoints.dart                   # Mobile/Tablet/Desktop/LargeDesktop
│   ├── breakpoint_builder.dart            # Widget responsive builder
│   └── app_shell.dart                     # Scaffold principale (BottomNav vs NavigationRail)
│
├── pages/
│   ├── welcome/                           # Schermate pre-autenticazione
│   │   ├── splash_screen.dart             # Splash iniziale, check auth
│   │   ├── welcome_page.dart              # Landing page
│   │   ├── login_page.dart                # Login email/password
│   │   └── registration_page.dart         # Registrazione nuovo utente
│   │
│   └── protected/                         # Area autenticata
│       ├── protected.dart                 # Scaffold principale con endDrawer admin
│       ├── home_page.dart                 # Dashboard con abbonamenti/certificati in scadenza
│       ├── calendar_page.dart             # Calendario corsi: filtro Tipologia, card in ordine cronologico
│       ├── course_management_page.dart    # CRUD corsi (crea/modifica/duplica)
│       ├── recurring_course_page.dart     # Gestione corsi ricorrenti
│       ├── admin_users_page.dart          # Lista utenti admin
│       ├── create_user_page.dart          # Creazione utente (solo admin)
│       ├── user_detail_page.dart          # Profilo/modifica utente (admin)
│       ├── admin_dashboard_page.dart      # Analytics (solo desktop)
│       └── debug_email_page.dart          # Invio email di test (solo kDebugMode)
│
├── api/                                   # Layer Firestore
│   ├── get_user_data.dart                 # Fetch singolo utente
│   ├── authentication/                    # CRUD e query utenti
│   │   ├── accept_regolamento.dart        # Accettazione regolamento
│   │   ├── get_users.dart                 # Tutti gli utenti (cache 5 min)
│   │   ├── create_user.dart               # Creazione utente
│   │   ├── update_user.dart               # Aggiornamento diff-based campi utente
│   │   ├── toggle_user_status.dart        # Attiva/disattiva utente
│   │   ├── get_users_with_expiring_subscriptions.dart
│   │   └── get_users_with_expiring_certificates.dart
│   ├── courses/                           # CRUD corsi + thin wrapper callable enrollment
│   │   ├── get_courses.dart               # Tutti i corsi (cache 1 min)
│   │   ├── create_course.dart
│   │   ├── update_course.dart
│   │   ├── delete_course.dart             # Callable admin atomica
│   │   ├── clean_courses.dart             # Rimozione corsi vecchi
│   │   ├── enrollment_callable.dart       # Helper condiviso per callable europe-west8
│   │   ├── join_waitlist.dart             # Callable joinWaitlist
│   │   ├── leave_waitlist.dart            # Callable leaveWaitlist
│   │   ├── recount_course_subscribed.dart # Callable admin ricalcolo contatore
│   │   ├── subscribe_to_course.dart       # Callable subscribeToCourse
│   │   ├── unsubscribe_to_course.dart     # Callable unsubscribeFromCourse
│   │   └── README_ISCRIZIONI.md           # Documentazione logica iscrizioni server-side
│   └── subscriptions/
│       └── assign_subscription.dart       # Callable admin assignSubscription
│
├── authentication/                        # Flussi auth lato client
│   ├── login.dart                         # Login + OneSignal.login + addEmail
│   ├── registration.dart
│   ├── logout.dart                        # Logout + OneSignal.logout
│   ├── is_logged.dart
│   ├── delete_user.dart
│   ├── reset_password.dart
│   └── resend_verification_email.dart
│
├── services/                              # Servizi esterni e facade
│   ├── onesignal_service.dart             # Conditional export web/mobile
│   ├── onesignal_mobile.dart              # Wrapper onesignal_flutter
│   ├── onesignal_web.dart                 # Binding dart:js_interop verso il bridge JS di web/index.html
│   ├── notification_service.dart          # Proxy/debug email via Cloud Functions
│   └── email_templates.dart               # Template HTML email
│
├── types/                                 # Modelli dati
│   ├── fitrope_user.dart                  # FitropeUser + CancelledEnrollment + TipologiaIscrizione
│   ├── course.dart                        # Course
│   ├── course_type.dart                   # Enum legacy open/personal_trainer (vedi TODO doppio binario)
│   └── user_subscription.dart             # UserSubscription + enum famiglia/billing
│
├── components/                            # Widget riusabili
│   ├── active_subscription_card.dart
│   ├── assign_subscription_card.dart
│   ├── calendar.dart                      # Calendario vendored da flutter_design_system
│   ├── course_card.dart
│   ├── course_preview_card.dart
│   ├── course_unsubscribe_button.dart     # Bottone disiscrizione color-coded
│   ├── custom_text_field.dart
│   ├── deferred_page.dart                 # Wrapper per route con deferred loading
│   ├── loader.dart
│   └── sala_selector_card.dart
│
└── utils/                                 # Helper e regole di dominio
    ├── course_unsubscribe_helper.dart     # Logica core disiscrizione
    ├── abbonamento_helper.dart            # Helper tipologie abbonamento
    ├── certificato_helper.dart            # Scadenza certificati
    ├── capacity_color.dart                # Colore riempimento corso
    ├── course_images.dart                 # Immagini corso per tipologia
    ├── course_tags.dart                   # Gestione tag corsi
    ├── course_types.dart                  # Registry tipologie/famiglie/sale default
    ├── get_course_state.dart
    ├── get_course_time_range.dart
    ├── get_tipologia_iscrizione_label.dart
    ├── format_date.dart
    ├── italian_time.dart                  # toItalianTime/italianTimestamp (Europe/Rome)
    ├── random_id.dart
    ├── regolamento_helper.dart
    ├── sale.dart                          # Lista chiusa Sale
    ├── snackbar_utils.dart
    ├── subscription_labels.dart           # Label UI nuovo modello abbonamenti
    ├── subscription_plans.dart            # Catalogo piani Open/Hyrox/PT
    ├── refresh_manager.dart               # Logica refresh cache
    ├── user_cache_manager.dart            # Cache dati utente
    ├── user_display_utils.dart
    └── waitlist_ui_helper.dart
```

## Modelli dati

### FitropeUser (`lib/types/fitrope_user.dart`)

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

- **UserSubscription** (`lib/types/user_subscription.dart`): `id?`, `planKey`, `family` (`SubscriptionFamily`: OPEN/HYROX/PT), `billingMode` (`BillingMode`: FREQUENCY/ENTRIES), `courseTypeTags` (accesso), `weeklyFrequency` (2/3/`null`=illimitato), `remainingEntries`, `startDate`, `endDate`.
- **Catalogo** (`lib/utils/subscription_plans.dart`): Open {2x, 3x, illimitato} x {1,3,6,12} = 12; Hyrox e PT 10 ingressi x {1,3,6,12}.
- **getCourseState (scope per famiglia):** gli abbonamenti che coprono la tipologia (tag) del corso ne determinano l'idoneita — FREQUENCY conta i corsi della stessa tipologia nella settimana (`null`=illimitato), ENTRIES verifica `remainingEntries > 0`; scadenza per-abbonamento. Accesso = tag legacy OPPURE copertura abbonamento; i corsi accessibili solo via tag (es. Hey Mamma) non hanno limiti di abbonamento.
- **Caveat modello misto:** se esiste almeno una voce viva nello snapshot, il modello multi-abbonamento vince sul fallback legacy in modo globale. I crediti legacy residui non vengono usati come fallback per famiglie non coperte; in fase gestionale conviene convertire/azzerare il residuo legacy quando si assegna un nuovo abbonamento.
- **Scadenza legacy:** nel fallback, `fineIscrizione == null` e considerata `EXPIRED`. Anche una data antecedente alla data del corso e `EXPIRED`; questo stato ha precedenza su `SUBSCRIBED`.

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
| courseType | CourseType | Tipologia legacy (`open` o `personal_trainer`); mantiene compatibilita con i documenti esistenti |
| imageKey | String? | Chiave di una immagine del catalogo `CourseImages`; se assente o invalida la UI usa il default della `courseType` |
| reminderEnabled | bool | Se true invia promemoria (default true) |
| waitlistEnabled | bool | Se true la lista d'attesa è attiva (default true) |
| sala | String? | Sala del corso (lista chiusa `Sale`: "Sala 1"/"Sala 2"; null = legacy/non impostata) |

I tag dei corsi sono in `CourseTags` (Personal Trainer, Open, **Hyrox**, Hey Mamma). Il registry `CourseTypes` (`lib/utils/course_types.dart`) mappa ogni tag a una tipologia con `displayName`, famiglia di abbonamento e `defaultSala` (quest'ultimo previsto per il futuro, non usato in v1). La tipologia per eligibility si deriva dai `tags` via `CourseTypes.primaryForTags`.

`Course.courseType` e un enum legacy limitato a Open/PT: il suo **unico** uso residuo e la scelta dell'immagine di default. Non usarlo per le regole di accesso, per raggruppare i corsi ne per rappresentare Hyrox e Hey Mamma. La UI mostra la tipologia reale tramite `CourseTypes.primaryForTags` + i token colore/icona di `lib/utils/course_type_style.dart`. `imageKey` deve essere una chiave valida di `CourseImages`, altrimenti la UI applica il default della `courseType`.

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

- **Mobile/Tablet**: `CustomBottomNavigationBar` (design system) con 2-3 tab (Home, Calendario, Utenti se admin)
- **Desktop**: `NavigationRail` laterale con 4 destinazioni (Home, Calendario, Utenti, Dashboard) + iniziali utente e pulsante logout

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

**Deferred loading**: `Protected`, `CourseManagementPage`, `RecurringCoursePage` e
`DebugEmailPage` sono importate con `deferred as` e wrappate in `DeferredPage(load: ...)`
(`lib/components/deferred_page.dart`), con preload avviato dallo splash: riducono il primo
caricamento web. Se aggiungi una route "pesante", segui lo stesso pattern.

## Regole di business

La parte piu delicata del progetto e la logica di iscrizione ai corsi.

Da PR4/PR5 le scritture del dominio iscrizioni sono server-side: il client mantiene le firme pubbliche in `lib/api/courses/`, ma i file Dart sono thin wrapper verso callable Cloud Functions in `europe-west8`. La logica autoritativa sta in `functions/src/enrollment/` (`eligibility.ts`, `refund.ts`, `subscription.ts`, `enrollment.ts`, `admin.ts`, più `notify.ts` per promemoria/waitlist, `courseTypes.ts`, `assignSubscription.ts`, `plansCatalog.ts`, `emailTemplates.ts`).

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
- La decisione di business corrente richiede idoneita immediata: a corso pieno, `getCourseState` restituisce lo stato di limite/scadenza invece di `CAN_WAITLIST` quando l'utente non potrebbe iscriversi direttamente.

### Cache

- Corsi: cache 1 minuto (`getAllCourses` in `get_courses.dart`)
- Utenti: cache 5 minuti (`getUsers`)
- Dopo operazioni su corsi o utenti, il codice invalida/aggiorna cache e store

Riferimenti:

- `lib/utils/course_unsubscribe_helper.dart`
- `lib/api/courses/README_ISCRIZIONI.md`
- `lib/api/courses/subscribe_to_course.dart`
- `lib/api/courses/unsubscribe_to_course.dart`
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
- **Web** (`lib/services/onesignal_web.dart`): **attivo** — binding `dart:js_interop` completo (init, login/logout, email, push opt-in/opt-out) verso il bridge JS definito in `web/index.html`, che carica il Web SDK v16 e registra il service worker.
- **Facade** (`lib/services/onesignal_service.dart`): `export ... if (dart.library.html)` per scelta automatica

Su web le email applicative passano via Cloud Function (`ensureOneSignalUser` crea l'utente server-side, poi `sendOneSignalNotification` invia). Il service worker sta in `web/push/onesignal/OneSignalSDKWorker.js` e viene registrato da `OneSignal.init` con scope calcolato dal `base href`. ATTENZIONE: l'appId in `lib/main.dart` è hardcoded ed è quello di produzione anche nella build staging (vedi TODO in CLAUDE.md).

### Flag per corso

Ogni `Course` ha due flag configurabili dall'admin in creazione/duplicazione:

- `reminderEnabled` (default true): se false, `scheduleTrialReminder` (server) salta l'invio per questo corso
- `waitlistEnabled` (default true): se false, `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`, `joinWaitlist` (server) rifiuta e `notifyWaitlistUsers` (server) salta l'invio

Entrambi si applicano anche ai corsi creati tramite `RecurringCoursePage`.

### Email certificati (solo emulatore e staging)

`functions/src/certificateEmails.ts`: `runCertificateEmails` invia il promemoria a chi ha
il certificato in scadenza tra 10 giorni e l'avviso a chi scade oggi (finestre giorno
DST-aware in Europe/Rome). Wiring in `index.ts` con **export condizionali**
(`APP_ENV=staging` o `FUNCTIONS_EMULATOR=true`): `certificateEmailsDaily` (onSchedule
08:00 Europe/Rome) e `sendTestCertificateEmail` (callable per DebugEmailPage). In
produzione NON vengono deployate finché la feature non viene promossa; in staging gli
invii restano filtrati dalla allowlist dentro `postToOneSignal`/ensure.

### Cloud Function

- Source: `functions/src/`
- Build: TypeScript → `functions/lib/`
- Test: Jest in `functions/src/__tests__/`
- Secret: `firebase functions:secrets:set ONESIGNAL_REST_API_KEY --project prod`
- Deploy: `firebase deploy --project prod --only functions`

### Preferenze utente

Ogni utente ha in Firestore `emailNotificationsEnabled` e `pushNotificationsEnabled` (default `true`). I trigger principali waitlist/trial reminder sono server-side in `functions/src/enrollment/notify.ts`; `notification_service.dart` resta per helper/proxy callable e invii manuali di debug.

## Dashboard Admin

`lib/pages/protected/admin_dashboard_page.dart` contiene:

- `AdminDashboardPage`: sezioni analisi utenti, corsi (ultimi 6 mesi) e abbonamenti con grafici a barre
- `UserListDrawer`: drawer laterale con lista utenti ricercabile (nome, email, telefono), aperto dalla dashboard o dall'area admin

La dashboard e visibile solo su desktop (`isDesktop(context)`). Il `Scaffold` in `protected.dart` gestisce l'`endDrawer` con la chiave globale `_scaffoldKey`.

## Testing

### Flutter (test/)

Test focalizzati su logica iscrizioni, serializzazione modelli, sale, course types, subscription plans/labels, update diff-based e waitlist. Suite principali:

- `active_subscriptions_state_test.dart`, `user_subscription_test.dart`, `subscription_plans_test.dart`, `subscription_labels_test.dart`
- `course_unsubscribe_test.dart`, `enrollment_new_logic_test.dart`, `enrollment_current_logic_test.dart`, `subscribe_restriction_test.dart`, `enrollment_mismatch_test.dart`
- `waitlist_state_test.dart`, `waitlist_operations_test.dart`, `course_flags_test.dart`, `course_state_edge_cases_test.dart`
- `create_course_test.dart`, `update_course_test.dart`, `update_user_test.dart`, `get_users_test.dart`, `course_correction_test.dart`
- `course_sala_serialization_test.dart`, `sale_test.dart`, `course_types_test.dart`, `course_type_test.dart`, `course_tags_test.dart`
- `notification_preferences_test.dart`, `email_templates_test.dart`, `italian_time_test.dart`, `capacity_color_test.dart`, `course_card_widget_test.dart`, `model_state_regression_test.dart`

Framework: `flutter_test` con `group()` e `setUp()`. Conteggio indicativo (si aggiorna a ogni PR, fonte: `flutter test`): ~326 test.

Esiste anche una suite E2E in `integration_test/` (login, subscribe, waitlist-swap, con
driver `test_driver/integration_test.dart`): 2 file su 3 sono in `skip: true` e nessun
workflow CI la esegue — vedi `integration_test/README.md` e il TODO in `CLAUDE.md`.

### Cloud Functions (functions/src/__tests__/)

Test Jest su handler OneSignal e dominio enrollment:

- `handler.test.ts` - auth, validazione payload, inoltro a OneSignal, errori
- `eligibility.test.ts`, `refund.test.ts`, `courseTypes.test.ts`, `enrollment.test.ts`
- `enrollmentHandlers.test.ts`, `adminHandlers.test.ts`, `assignSubscription.test.ts`
- `notify.test.ts`, `notifyOrchestration.test.ts`, `conventions.test.ts`
- `certificateEmails.test.ts` (finestre giorno Europe/Rome, selezione destinatari, run)
- `indexExports.test.ts` (gate ambiente delle funzioni certificati)

Framework: `jest` + `ts-jest`. Conteggio indicativo (fonte: `cd functions && npm test`): ~272 test.

### Integration tests emulatori

I test in `functions/src/__integration__/` girano su Firebase Emulator Suite:

- `enrollment.integration.test.ts` - callable reali, transazioni, concorrenza, authz
- `firestoreRules.integration.test.ts` - lockdown field-level e payload reali con `@firebase/rules-unit-testing`

Esegui con `cd functions && npm run test:integration`. Richiede Java 21+ e firebase-tools 15.x; in CI e un gate del job `functions-integration`, presente in tutti e tre i workflow (`ci.yml`, `staging.yml`, `release.yml`). Il secret dell'emulatore si passa scrivendo `functions/.secret.local` (gitignored), non via env var.

## CI/CD

### GitHub Actions

**ci.yml** (Pull Request verso `main`/`develop` + avvio manuale):

- `test`: `flutter pub get` -> `flutter test` -> `flutter analyze --no-fatal-infos` -> `dart format --set-exit-if-changed .` -> `flutter build web --wasm --release`
- `functions-test`: Node 24 per compatibilita tooling CI, `npm ci`, `npm run build`, `npm test`
- `functions-integration`: Node 22 runtime-aligned + Java 21 + firebase-tools 15, `npm run test:integration` con project `demo-fitrope`

Nota operativa: `flutter analyze --no-fatal-infos` e parte della CI; gli info-level restano debito tecnico ma non bloccano il job.

**staging.yml** (push su `develop` + avvio manuale) — è il workflow che governa l'ambiente staging:

- gate in parallelo: `flutter-test-and-build` (test, analyze, format, build web con `APP_ENV=staging` e `--base-href /fitrope_app/`, upload artifact Pages), `functions-test` (Node 24), `functions-integration` (Node 22 + Java 21 + Emulator Suite)
- poi il deploy in sequenza **vincolata**: `deploy-functions` (+ seed dati sintetici) -> `deploy-pages` -> `deploy-rules` -> `smoke-test`. Le callable prima della web nuova, le rules per ultime (bloccano le scritture dirette del client vecchio)
- `smoke-test`: `curl` su `index.html`/`version.json`/`flutter_bootstrap.js` del sito Pages + `firebase functions:list` con assert su tutte le callable enrollment
- auth via OIDC/Workload Identity Federation (`google-github-actions/auth@v3`), nessuna service-account key nel repo; il seed usa un access token federato (`GOOGLE_OAUTH_ACCESS_TOKEN`)
- `concurrency: staging-deploy` con `cancel-in-progress`: un push nuovo annulla il deploy in corso

**release.yml** (push e Pull Request sul branch `release`):

- **Valida soltanto**: `validation` (test, analyze, format, build web wasm), `functions` (`npm test -- --runInBand`, come staging.yml), `functions-integration`
- Non crea GitHub Release e non pubblica su Pages: la produzione resta un deploy manuale

**version-bump.yml** (PR chiusa con merge su `main`) — l'unico workflow che SCRIVE sul repo:

- bump patch della versione in `pubspec.yaml` e push diretto su `main` (`permissions: contents: write`)
- skip sui titoli `chore: bump version` / `[skip ci]` per non auto-innescarsi
- è il motivo per cui la "Versione app" in questa guida va trattata come indicativa

**Produzione**: https://app.fithousemonza.it (Hostinger, deploy manuale, progetto Firebase `fit-rope-app-1f575`).

**Staging**: https://fgrotta.github.io/fitrope_app/ (GitHub Pages via `actions/deploy-pages` da artifact — nessun branch `gh-pages` coinvolto — pubblicato da `develop`, progetto Firebase `fit-rope-staging`).

### Dependabot

- Aggiornamenti settimanali (lunedi ore 9:00 UTC)
- Traccia dipendenze pub e github-actions
- Assegnato a `dellarosamarco`

## Comandi utili

### Flutter

```bash
flutter pub get
flutter test
flutter analyze --no-fatal-infos
dart format --set-exit-if-changed .
flutter build web --wasm --release
flutter run -d chrome
```

### Cloud Functions

```bash
# Sviluppo locale
cd functions
npm ci                 # installazione riproducibile (runtime Functions Node 22; unit CI verifica anche Node 24)
npm run build          # compila TypeScript
npm test               # test Jest unitari
npm run test:integration # Emulator Suite, richiede Java 21+
npm run seed:emulator  # seed dati sintetici su emulatori avviati
npm run seed:staging   # seed sintetico su staging (richiede STAGING_PROJECT_ID + credenziali)
npm run serve          # avvia emulatore Firebase Functions

# Deploy — .firebaserc NON ha un alias default: --project e sempre obbligatorio
firebase deploy --project prod --only functions            # deploy in produzione (= npm run deploy)
firebase functions:secrets:set ONESIGNAL_REST_API_KEY --project prod   # setup/aggiorna secret
firebase functions:log --project prod --only sendOneSignalNotification # vedi log runtime
firebase functions:delete sendOneSignalNotification --project prod     # elimina la function
```

Il predeploy in `firebase.json` compila TypeScript automaticamente via `./node_modules/.bin/tsc` (invocazione diretta senza npm per evitare il bug stdin di npm 10+).

**Setup iniziale** (una volta sola per ambiente):

1. `firebase login`
2. `firebase functions:secrets:set ONESIGNAL_REST_API_KEY --project prod` (incolla la REST API Key OneSignal)
3. `firebase deploy --project prod --only functions`

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

- Il CRUD corsi resta client-side: migrare create/update a callable Admin SDK, eliminando la duplicazione `id`/`uid` e centralizzando validazione e autorizzazioni.
- `flutter analyze` emette ancora issue info-level; la CI usa `--no-fatal-infos`, quindi non bloccano il merge ma restano debito tecnico da ridurre.

## Osservazioni operative

- I file Dart sono in `snake_case` (es. `home_page.dart`, non `HomePage.dart`): il repo e stato rinominato interamente da camelCase. Se rinomini file o classi, ricontrolla sempre la compatibilita con filesystem case-sensitive.
- Il codice usa ancora molti `print` e side effect diretti nei widget; prima di grandi refactor, separa i cambiamenti di dominio da quelli UI.
- Non usare path assoluti nei file di documentazione: usa sempre path relativi alla root del progetto.
- Nessun sistema di code generation (build_runner, freezed, json_serializable): la serializzazione e manuale con `toJson()`/`fromJson()`.
- Due ambienti Firebase separati: `fit-rope-app-1f575` (prod) e `fit-rope-staging` (staging), selezionati a compile-time con `--dart-define=APP_ENV=staging` (vedi `lib/app_environment.dart`). Non esiste un ambiente `dev` distinto: per lo sviluppo si usa la Emulator Suite locale.
- Localizzazione hardcoded in italiano, nessun file .arb: le stringhe UI sono direttamente nel codice.
- Nelle Cloud Functions importa `Timestamp` e `FieldValue` da `firebase-admin/firestore`, non da `admin.firestore.*`, per compatibilita con runtime emulato.

## Dove intervenire in base al task

| Area | File principali |
|---|---|
| Login, logout, verifica email, reset password | `lib/authentication/`, `lib/pages/welcome/` |
| Sessione e loading overlay | `lib/state/`, `lib/pages/protected/protected.dart` |
| Gestione utenti admin | `lib/pages/protected/admin_users_page.dart`, `create_user_page.dart`, `user_detail_page.dart`, `lib/api/authentication/` |
| Gestione corsi | `lib/pages/protected/course_management_page.dart`, `recurring_course_page.dart`, `lib/api/courses/` |
| Regole iscrizione/disiscrizione | `functions/src/enrollment/`, `lib/api/courses/`, `lib/utils/get_course_state.dart`, `lib/utils/course_unsubscribe_helper.dart`, `test/` |
| Waitlist corsi | `lib/api/courses/join_waitlist.dart`, `leave_waitlist.dart`, `lib/utils/waitlist_ui_helper.dart` |
| Abbonamenti multi-famiglia | `lib/types/user_subscription.dart`, `lib/utils/subscription_plans.dart`, `lib/utils/subscription_labels.dart`, `lib/api/subscriptions/`, `functions/src/enrollment/subscription.ts` |
| Sale e tipologie corso | `lib/utils/sale.dart`, `lib/utils/course_types.dart`, `lib/utils/course_tags.dart`, `lib/components/sala_selector_card.dart` |
| Firestore rules e emulatori | `firestore.rules`, `firebase.json`, `docs/AMBIENTI_DI_TEST.md`, `functions/src/__integration__/` |
| Notifiche push/email | `lib/services/notification_service.dart`, `lib/services/email_templates.dart`, `functions/src/` |
| Test email manuale (debug) | `lib/pages/protected/debug_email_page.dart`, `lib/services/notification_service.dart` (`sendTestWaitlistEmail`, `sendTestTrialReminderEmail`) |
| OneSignal SDK | `lib/services/onesignal_*.dart`, `web/index.html` (bridge JS + init SDK v16), `web/push/onesignal/OneSignalSDKWorker.js` |
| Dashboard e analisi | `lib/pages/protected/admin_dashboard_page.dart` |
| Layout e breakpoints | `lib/layout/` |
| Stili globali | `lib/style.dart`, `lib/components/` |

## Regole per gli agenti

- Parti sempre dai file reali, non dal `README.md`.
- Se modifichi logica di iscrizione, allinea client display (`get_course_state.dart` / `course_unsubscribe_helper.dart`) e server enforcement (`functions/src/enrollment/`).
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
