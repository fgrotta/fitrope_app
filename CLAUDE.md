# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `AGENTS.md`.

## Comandi

### Flutter

```bash
flutter pub get          # installa dipendenze
flutter test             # esegui tutti i test
flutter analyze          # analisi statica
flutter format --set-exit-if-changed .  # check formattazione
flutter build web --debug               # build web
flutter run -d chrome                   # avvio locale
```

### Cloud Functions (functions/)

```bash
cd functions
npm install              # installa dipendenze Node
npm run build            # compila TypeScript
npm test                 # Jest sull'handler OneSignal
```

### Deploy e gestione secret

```bash
# Deploy (il predeploy compila automaticamente via tsc)
firebase deploy --only functions

# Aggiornare il secret OneSignal REST API Key
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
firebase deploy --only functions   # re-deploy per bindare il nuovo valore

# Vedere i log runtime
firebase functions:log --only sendOneSignalNotification

# Eliminare la function
firebase functions:delete sendOneSignalNotification
```

Dopo ogni modifica, esegui almeno `flutter test` e `flutter analyze`. Se tocchi `functions/`, esegui anche `npm test` nella cartella `functions/`.

## Verifica live e lezioni operative

Lezioni dal lavoro di sviluppo UI (verifica delle modifiche nel browser):

- `flutter run -d web-server` **ricompila solo all'avvio o su hot-restart** (`R` da stdin). Un'istanza lanciata in background non riceve `R`: dopo ogni modifica al codice **riavvia il run** (kill della porta + relaunch), non basta ricaricare la pagina.
- Il browser serve un `main.dart.js` cache-ato: dopo il relaunch fai un **hard reload** (Cmd/Ctrl+Shift+R), altrimenti vedi il build vecchio (sintomo tipico: il default sembra sbagliato o "la modifica non ha effetto").
- Per testare i **breakpoint responsive** verifica la larghezza reale (`window.innerWidth`): il ridimensionamento della finestra può essere inaffidabile. Breakpoint in `lib/layout/breakpoints.dart` (mobile <600, tablet <900, desktop <1600, largeDesktop ≥1600).
- **Pre-commit hook**: in alcuni ambienti `flutter` riporta SDK `0.0.0-unknown` e l'hook fallisce anche con test/analyze verdi → committa con `--no-verify` **dopo** aver eseguito a mano `flutter analyze` + `flutter test`.

### UI responsive / layout shift

- Liste di card (es. `CalendarPage`): su desktop usa griglie multi-colonna con `LayoutBuilder` (n. colonne = larghezza disponibile / larghezza-min-card) e disposizione "masonry" per gestire le altezze variabili; evita la singola colonna stretta che spreca lo spazio orizzontale.
- Per un default che dipende dal layout (es. vista mese su desktop, settimana su mobile) usa uno stato **nullable** (`bool?`) risolto a runtime con `valore ?? isDesktop(context)`: così il default segue il breakpoint ma il toggle manuale dell'utente mantiene la precedenza.
- Evita stringhe **transitorie di caricamento** dentro una `description` condivisa renderizzata riga-per-riga (`CourseCard._buildMetadata`): appaiono e poi spariscono al termine della fetch → **salto di altezza** della card a ogni rebuild. I dati finali vanno in widget stabili (pill di conteggio, dialog, box dedicato), non nei metadati testuali.

## Convenzioni

- UI in italiano. Non tradurre stringhe UI in inglese salvo richiesta esplicita.
- Localizzazione date: `it_IT` via `intl`. Usa `formatDate` da `lib/utils/formatDate.dart`.
- Serializzazione manuale: se aggiungi/modifichi campi nei modelli, aggiorna sempre sia `toJson` sia `fromJson` in `lib/types/`.
- Nomi file Dart: rispetta il case esatto (es. `HomePage.dart`, non `homepage.dart`).
- Stato globale Redux minimale: non aggiungere campi a `AppState` senza necessita reale.
- Dopo mutazioni su corsi/utenti, invalida la cache (`refresh_manager`, `user_cache_manager`).
- Usa transazioni Firestore per operazioni che toccano contemporaneamente utente e corso.

## Aree sensibili

La logica di iscrizione/disiscrizione ai corsi e la parte piu critica. Se la modifichi:

1. Leggi `lib/api/courses/README_ISCRIZIONI.md`
2. Esegui i test: `flutter test`
3. File chiave: `lib/api/courses/subscribeToCourse.dart`, `unsubscribeToCourse.dart`, `lib/utils/course_unsubscribe_helper.dart`

### Notifiche OneSignal

- REST API key **non** nel codice Flutter: sta in Google Secret Manager, usata solo dalla Cloud Function.
- Se modifichi il payload inviato a OneSignal, non includere `app_id` — lo inietta la function server-side.
- `notification_service.dart` chiama `FirebaseFunctions.instance.httpsCallable('sendOneSignalNotification')`.
- Su web le chiamate dirette a OneSignal falliscono per CORS: passa sempre dalla Cloud Function.
- **Push web disabilitate**: il Web SDK OneSignal è commentato in `web/index.html` e `onesignal_web.dart` è no-op. Le email su web passano via Cloud Function `ensureOneSignalUser` (creazione utente server-side) + `sendOneSignalNotification`. Le push native restano attive su Android/iOS via `onesignal_flutter`.
- Ogni corso ha i flag `reminderEnabled` e `waitlistEnabled`: se false, `scheduleTrialReminder` / `notifyWaitlistUsers` saltano l'invio e `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`.
- **Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).
- **Debug email**: in `kDebugMode` è disponibile un FAB in `Protected` che apre `DebugEmailPage` (`/debug-email`). Permette di inviare email di test (waitlist e promemoria prova) all'utente corrente senza triggering reale degli eventi. Le funzioni `sendTestWaitlistEmail` / `sendTestTrialReminderEmail` sono in `notification_service.dart`.

## Struttura rapida

- Entry point: `lib/main.dart`
- Route: `lib/router.dart` (7 route statiche + 1 debug-only)
- Stato: `lib/state/` (Redux con thunk)
- Pagine: `lib/pages/welcome/` (auth) e `lib/pages/protected/` (area protetta)
- API Firestore: `lib/api/` (authentication + courses)
- Modelli: `lib/types/fitropeUser.dart`, `lib/types/course.dart`
- Layout responsive: `lib/layout/` (breakpoints + AppShell)
- Servizi esterni: `lib/services/` (OneSignal mobile + web, notifiche, email templates)
- Cloud Functions: `functions/src/` (TypeScript, proxy OneSignal)
