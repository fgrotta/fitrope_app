# FitRope Agent Guide

## Scopo del progetto

FitRope e una app Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Il backend applicativo e Firebase:

- `firebase_auth` per login, registrazione e verifica email
- `cloud_firestore` per utenti, corsi e stato iscrizioni
- Redux minimale per lo stato globale di sessione e lista corsi

L'app e localizzata principalmente in italiano e il brand esposto in UI e `Fit House`, mentre il package resta `fitrope_app`.

## Stack e dipendenze chiave

| Componente | Dettaglio |
|---|---|
| Flutter SDK | `>=3.5.0-180.3.beta <4.0.0` |
| Flutter CI | `3.24.0` stable |
| Stato globale | `redux`, `redux_thunk`, `flutter_redux` |
| Backend | `firebase_core`, `firebase_auth`, `cloud_firestore` |
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
3. `initializeDateFormatting('it_IT', null)`
4. `SafeArea` + `StoreProvider(store)` wrapping `MyApp`
5. `MaterialApp` con locale `it_IT`, route iniziale `SPLASH_ROUTE`

## Mappa delle cartelle

```
lib/
├── main.dart                        # Bootstrap Firebase + MaterialApp
├── router.dart                      # Definizione 7 route statiche
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
│       └── AdminDashboardPage.dart  # Analytics (solo desktop)
│
├── api/                             # Layer Firestore
│   ├── getUserData.dart             # Fetch singolo utente
│   ├── authentication/              # CRUD e query utenti
│   │   ├── getUsers.dart            # Tutti gli utenti (cache 5 min)
│   │   ├── createUser.dart          # Creazione utente
│   │   ├── updateUser.dart          # Aggiornamento campi utente
│   │   ├── deleteUser.dart          # Eliminazione utente
│   │   ├── toggleUserStatus.dart    # Attiva/disattiva utente
│   │   ├── getUsersWithExpiringSubscriptions.dart
│   │   └── getUsersWithExpiringCertificates.dart
│   └── courses/                     # CRUD corsi e logica iscrizioni
│       ├── getCourses.dart          # Tutti i corsi (cache 1 min)
│       ├── createCourse.dart
│       ├── updateCourse.dart
│       ├── deleteCourse.dart
│       ├── cleanCourses.dart        # Rimozione corsi vecchi
│       ├── subscribeToCourse.dart   # Iscrizione con transazione
│       ├── unsubscribeToCourse.dart # Disiscrizione con refund tracking
│       ├── updateCourseSubscribedCount.dart
│       └── README_ISCRIZIONI.md     # Documentazione logica iscrizioni
│
├── authentication/                  # Flussi auth lato client
│   ├── login.dart
│   ├── registration.dart
│   ├── logout.dart
│   ├── isLogged.dart
│   ├── deleteUser.dart
│   ├── resetPassword.dart
│   └── resendVerificationEmail.dart
│
├── types/                           # Modelli dati
│   ├── fitropeUser.dart             # FitropeUser + CancelledEnrollment + TipologiaIscrizione
│   └── course.dart                  # Course
│
├── components/                      # Widget riusabili
│   ├── course_card.dart
│   ├── course_preview_card.dart
│   ├── course_unsubscribe_button.dart  # Bottone disiscrizione color-coded
│   ├── custom_text_field.dart
│   └── loader.dart
│
└── utils/                           # Helper e regole di dominio
    ├── course_unsubscribe_helper.dart  # Logica core disiscrizione
    ├── abbonamento_helper.dart         # Helper tipologie abbonamento
    ├── certificato_helper.dart         # Scadenza certificati
    ├── course_tags.dart                # Gestione tag corsi
    ├── getCourseState.dart
    ├── getCourseTimeRange.dart
    ├── getTipologiaIscrizioneLabel.dart
    ├── formatDate.dart
    ├── randomId.dart
    ├── snackbar_utils.dart
    ├── refresh_manager.dart            # Logica refresh cache
    ├── user_cache_manager.dart         # Cache dati utente
    └── user_display_utils.dart
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

### TipologiaIscrizione (enum)

- `PACCHETTO_ENTRATE` - Pacchetto a ingressi
- `ABBONAMENTO_MENSILE` - Mensile
- `ABBONAMENTO_TRIMESTRALE` - Trimestrale
- `ABBONAMENTO_SEMESTRALE` - Semestrale
- `ABBONAMENTO_ANNUALE` - Annuale
- `ABBONAMENTO_PROVA` - Prova

### CancelledEnrollment (nested in FitropeUser)

Traccia le disiscrizioni con: `courseId`, `cancelledAt`, `entryLost` (se l'ingresso e stato perso), `courseStartDate`.

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

`CourseManagementPage` accetta argomenti: `courseToEdit`, `courseToDuplicate`, `mode`.

## Regole di business

La parte piu delicata del progetto e la logica di iscrizione ai corsi.

### Iscrizione

- **Pacchetto entrate**: decrementa `entrateDisponibili` di 1
- **Abbonamenti temporali**: controlla limite settimanale (`entrateSettimanali`) e validita abbonamento
- Usa transazioni Firestore per sicurezza concorrente (check capacita + iscrizione atomica)

### Disiscrizione

- **Pacchetto entrate, > 8 ore prima**: rimborso completo credito (`unsubscribeToCourse`)
- **Pacchetto entrate, <= 8 ore prima**: dialog di conferma, se confermato nessun rimborso (`forceUnsubscribeWithNoRefund`)
- **Abbonamenti temporali**: rimborso posto sempre, nessun impatto crediti
- **Admin**: rimborso crediti sempre, indipendentemente dal tempo

### Restrizioni ruolo

- Admin e Trainer non dovrebbero iscriversi ai corsi come utenti normali

### Cache

- Corsi: cache 1 minuto (`getCourses`)
- Utenti: cache 5 minuti (`getUsers`)
- Dopo operazioni su corsi o utenti, il codice invalida/aggiorna cache e store

Riferimenti:

- `lib/utils/course_unsubscribe_helper.dart`
- `lib/api/courses/README_ISCRIZIONI.md`
- `lib/api/courses/subscribeToCourse.dart`
- `lib/api/courses/unsubscribeToCourse.dart`

Se tocchi queste aree, aggiorna o aggiungi test in `test/`.

## Firebase

- **Progetto**: `fit-rope-app-1f575`
- **Auth domain**: `fit-rope-app-1f575.firebaseapp.com`
- **Piattaforme**: Web, Android, iOS, macOS, Windows
- **Config**: `lib/firebase_options.dart` (auto-generato da FlutterFire CLI)

### Collezioni Firestore

- `users` - documenti utente con dati abbonamento e iscrizioni
- `courses` - documenti corso con orario e capacita

### Pattern

- Transazioni per operazioni atomiche (iscrizione/disiscrizione)
- Server timestamp per audit trail
- Invalidazione cache dopo mutazioni

## Dashboard Admin

`lib/pages/protected/AdminDashboardPage.dart` contiene:

- `AdminDashboardPage`: sezioni analisi utenti, corsi (ultimi 6 mesi) e abbonamenti con grafici a barre
- `UserListDrawer`: drawer laterale con lista utenti ricercabile (nome, email, telefono), aperto dalla dashboard o dall'area admin

La dashboard e visibile solo su desktop (`isDesktop(context)`). Il `Scaffold` in `Protected.dart` gestisce l'`endDrawer` con la chiave globale `_scaffoldKey`.

## Testing

6 file di test in `test/`, focalizzati sulla logica di business delle iscrizioni:

| File | Focus |
|---|---|
| `course_unsubscribe_test.dart` | Logica core disiscrizione |
| `enrollment_new_logic_test.dart` | Nuove regole iscrizione |
| `enrollment_current_logic_test.dart` | Stato iscrizione corrente |
| `enrollment_mismatch_test.dart` | Casi edge mismatch |
| `subscribe_restriction_test.dart` | Restrizioni per abbonamento |
| `course_correction_test.dart` | Correzioni dati corso |

Framework: `flutter_test` con `group()` e `setUp()` per organizzazione.

## CI/CD

### GitHub Actions

**ci.yml** (branch `main`, `develop`):

```
flutter pub get → flutter test → flutter analyze → flutter format --set-exit-if-changed . → flutter build web --debug
```

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

```bash
flutter pub get
flutter test
flutter analyze
flutter format --set-exit-if-changed .
flutter build web --debug
flutter run -d chrome
```

## Osservazioni operative

- Se rinomini file o classi, ricontrolla sempre la compatibilita con filesystem case-sensitive (es. `HomePage.dart` non `Homepage.dart`).
- Il codice usa ancora molti `print` e side effect diretti nei widget; prima di grandi refactor, separa i cambiamenti di dominio da quelli UI.
- Non usare path assoluti nei file di documentazione: usa sempre path relativi alla root del progetto.
- Nessun sistema di code generation (build_runner, freezed, json_serializable): la serializzazione e manuale con `toJson()`/`fromJson()`.
- Nessuna separazione ambienti (dev/staging/prod): un unico progetto Firebase.
- Localizzazione hardcoded in italiano, nessun file .arb: le stringhe UI sono direttamente nel codice.

## Dove intervenire in base al task

| Area | File principali |
|---|---|
| Login, logout, verifica email, reset password | `lib/authentication/`, `lib/pages/welcome/` |
| Sessione e loading overlay | `lib/state/`, `lib/pages/protected/Protected.dart` |
| Gestione utenti admin | `lib/pages/protected/AdminUsersPage.dart`, `CreateUserPage.dart`, `UserDetailPage.dart`, `lib/api/authentication/` |
| Gestione corsi | `lib/pages/protected/CourseManagementPage.dart`, `RecurringCoursePage.dart`, `lib/api/courses/` |
| Regole iscrizione/disiscrizione | `lib/api/courses/`, `lib/utils/course_unsubscribe_helper.dart`, `test/` |
| Dashboard e analisi | `lib/pages/protected/AdminDashboardPage.dart` |
| Layout e breakpoints | `lib/layout/` |
| Stili globali | `lib/style.dart`, `lib/components/` |

## Regole per gli agenti

- Parti sempre dai file reali, non dal `README.md`.
- Se modifichi logica di iscrizione, esegui almeno i test in `test/` relativi a corsi e abbonamenti.
- Se tocchi import o rename file, controlla la compatibilita con filesystem case-sensitive.
- Mantieni la UI in italiano salvo requisito esplicito diverso.
- Quando aggiungi campi ai modelli Firestore, aggiorna sia `toJson` sia `fromJson`.
- Dopo operazioni su corsi o utenti, assicurati di invalidare/aggiornare cache e Redux store.
- Usa transazioni Firestore per qualsiasi operazione che modifica contemporaneamente utente e corso.
