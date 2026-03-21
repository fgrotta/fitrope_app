# FitRope Agent Guide

## Scopo del progetto

FitRope e una app Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Il backend applicativo e Firebase:

- `firebase_auth` per login, registrazione e verifica email
- `cloud_firestore` per utenti, corsi e stato iscrizioni
- Redux minimale per lo stato globale di sessione e lista corsi

L'app e localizzata principalmente in italiano e il brand esposto in UI e `Fit House`, mentre il package resta `fitrope_app`.

## Stack e dipendenze chiave

- Flutter SDK richiesto dal progetto: `>=3.5.0-180.3.beta <4.0.0`
- CI configurata con Flutter `3.24.0`
- Design system esterno: `flutter_design_system` da GitHub
- Stato globale: `redux`, `redux_thunk`, `flutter_redux`
- Firebase bootstrap in `lib/main.dart`

Prima di modificare dipendenze o CI, verifica la compatibilita tra SDK dichiarato e versione usata nei workflow.

## Entry points

- App bootstrap: `lib/main.dart`
- Routing statico: `lib/router.dart`
- Store Redux: `lib/state/store.dart`
- Workflow protetto post-login: `lib/pages/protected/Protected.dart`

Route iniziale: splash screen (`SPLASH_ROUTE`), poi transizione verso welcome/login o area protetta.

## Mappa delle cartelle

- `lib/pages/welcome`: splash, welcome, login, registration
- `lib/pages/protected`: home, calendario, gestione corsi, utenti admin, dashboard admin
- `lib/api/authentication`: CRUD e query utenti su Firestore
- `lib/api/courses`: CRUD corsi e logica di iscrizione/disiscrizione
- `lib/authentication`: flussi auth lato client
- `lib/components`: widget riusabili
- `lib/layout`: `app_shell.dart`, `breakpoints.dart`, `breakpoint_builder.dart`
- `lib/types`: modelli `FitropeUser` e `Course`
- `lib/utils`: regole dominio, cache, snackbar, helper abbonamenti
- `test`: test focalizzati soprattutto sulle regole di iscrizione/disiscrizione

## Layout responsive

L'app usa un sistema di breakpoint definito in `lib/layout/breakpoints.dart`. Il widget `AppShell` (`lib/layout/app_shell.dart`) switcha automaticamente tra:

- **Mobile**: `BottomNavigationBar`
- **Desktop**: `NavigationRail` laterale con avatar/iniziali utente e pulsante logout

Usa sempre `isDesktop(context)` o `breakpointOf(context)` per decisioni di layout. La `AdminDashboardPage` e disponibile solo su desktop.

## Stato globale e modello dati

Lo `AppState` contiene solo:

- `user`
- `isLoading`
- `allCourses`

I modelli principali sono:

- `lib/types/fitropeUser.dart`
- `lib/types/course.dart`

Dettagli dominio importanti:

- ruoli supportati: almeno `Admin`, `Trainer`, `User`
- iscrizioni supportate: pacchetto entrate, abbonamenti temporali, abbonamento prova
- l'utente traccia `cancelledEnrollments` per gestire disiscrizioni con perdita credito/ingresso
- i corsi hanno `capacity`, `subscribed`, `trainerId` e `tags`

## Dashboard Admin

`lib/pages/protected/AdminDashboardPage.dart` contiene:

- `AdminDashboardPage`: sezioni analisi utenti, corsi (ultimi 6 mesi) e abbonamenti con grafici a barre
- `UserListDrawer`: drawer laterale con lista utenti ricercabile (nome, email, telefono), aperto dalla dashboard o dall'area admin

La dashboard e visibile solo su desktop (`isDesktop(context)`). Il `Scaffold` in `Protected.dart` gestisce l'`endDrawer` con la chiave globale `_scaffoldKey`.

## Regole di business gia presenti

La parte piu delicata del progetto e la logica di iscrizione ai corsi.

- Disiscrizione pacchetto entrate: soglia 8 ore
- Disiscrizione abbonamenti temporali: soglia 4 ore
- Admin e Trainer non dovrebbero iscriversi ai corsi come utenti normali
- Dopo operazioni su corsi o utenti, il codice invalida/aggiorna cache e store

Riferimenti:

- `lib/utils/course_unsubscribe_helper.dart`
- `lib/api/courses/README_ISCRIZIONI.md`

Se tocchi queste aree, aggiorna o aggiungi test in `test/`.

## Comandi utili

```bash
flutter pub get
flutter test
flutter analyze
flutter format --set-exit-if-changed .
flutter build web --debug
```

CI corrente in `.github/workflows/ci.yml`:

- `flutter pub get`
- `flutter test`
- `flutter analyze`
- `flutter format --set-exit-if-changed .`
- build debug `web`

## Osservazioni operative importanti

- `README.md` descrive ora il progetto reale; in caso di conflitto, il codice resta comunque la fonte primaria.
- Nel workspace sono presenti `web/` e `windows/`; la documentazione e la CI sono state riallineate al perimetro web.
- Se rinomini file o classi, ricontrolla sempre la compatibilita con filesystem case-sensitive (es. `HomePage.dart` non `Homepage.dart`).
- Il codice usa ancora molti `print` e side effect diretti nei widget; prima di grandi refactor, separa i cambiamenti di dominio da quelli UI.
- Non usare path assoluti nei file di documentazione: usa sempre path relativi alla root del progetto.

## Dove intervenire in base al task

- Login, logout, verifica email, reset password: `lib/authentication/` e `lib/pages/welcome/`
- Problemi di sessione o loading overlay: `lib/state/` e `lib/pages/protected/Protected.dart`
- Gestione utenti admin: `lib/pages/protected/AdminUsersPage.dart`, `CreateUserPage.dart`, `UserDetailPage.dart`, `lib/api/authentication/`
- Gestione corsi: `lib/pages/protected/CourseManagementPage.dart`, `RecurringCoursePage.dart`, `lib/api/courses/`
- Regole iscrizione/disiscrizione: `lib/api/courses/`, `lib/utils/course_unsubscribe_helper.dart`, test in `test/`
- Dashboard e analisi: `lib/pages/protected/AdminDashboardPage.dart`
- Layout e breakpoints: `lib/layout/`
- Stili globali: `lib/style.dart` e componenti in `lib/components/`

## Regole per gli agenti

- Parti sempre dai file reali, non dal `README.md`.
- Se modifichi logica di iscrizione, esegui almeno i test in `test/` relativi a corsi e abbonamenti.
- Se tocchi import o rename file, controlla la compatibilita con filesystem case-sensitive.
- Mantieni la UI in italiano salvo requisito esplicito diverso.
- Quando aggiungi campi ai modelli Firestore, aggiorna sia `toJson` sia `fromJson`.
