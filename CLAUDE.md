# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `agents.md`.

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
npm test                 # Jest (handler OneSignal + dominio enrollment)
npm run test:integration # test integrazione su Emulator Suite (richiede Java 21 nel PATH)
```

### Ambiente di test locale (Firebase Emulator Suite)

Il QA manuale si fa sull'emulatore, MAI in produzione (vedi `docs/AMBIENTI_DI_TEST.md`).
Richiede Java 21+ (keg-only via Homebrew: anteporre al PATH).

```bash
cd functions && npm run build && cd ..
PATH="/usr/local/opt/openjdk@21/bin:$PATH" firebase emulators:start   # Auth+Firestore+Functions+UI (localhost:4000)
cd functions && npm run seed:emulator    # dati sintetici (password utenti: test1234)
flutter run -d chrome --dart-define=USE_EMULATOR=true                 # app contro gli emulatori
```

Nel codice functions usare SEMPRE `import { Timestamp, FieldValue } from "firebase-admin/firestore"`
(il namespace `admin.firestore.*` perde le statiche nel runtime emulato).

### Deploy e gestione secret

```bash
# Deploy (il predeploy compila automaticamente via tsc)
firebase deploy --only functions

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

Dopo ogni modifica, esegui almeno `flutter test` e `flutter analyze`. Se tocchi `functions/`, esegui anche `npm test` nella cartella `functions/`.

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
