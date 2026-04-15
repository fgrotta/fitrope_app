# FitRope

FitRope e una applicazione Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Nel codice UI il brand esposto e `Fit House`, mentre il package del progetto resta `fitrope_app`.

## Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Cloud Functions (TypeScript, proxy verso OneSignal)
- OneSignal (push + email, mobile SDK + Web SDK)
- Redux + `flutter_redux`
- `flutter_design_system` come dipendenza Git esterna

## Funzionalita principali

- login, registrazione, reset password e verifica email
- area protetta con navigazione responsive tra home, calendario e strumenti admin
- gestione corsi e corsi ricorrenti
- regole di iscrizione/disiscrizione basate su ruolo e tipologia di abbonamento
- lista d'attesa (waitlist) con notifiche automatiche quando si libera un posto
- promemoria email/push per lezioni di prova (schedulati la sera prima)
- preferenze notifiche utente (push e email, attivabili singolarmente)
- dashboard admin con analisi utenti, corsi e abbonamenti (solo desktop)
- deploy web tramite GitHub Actions

## Layout responsive

L'app si adatta automaticamente:

- **Mobile**: bottom navigation bar
- **Desktop**: navigation rail laterale con avatar utente e logout

## Struttura del progetto

- `lib/main.dart`: bootstrap Firebase e MaterialApp
- `lib/router.dart`: definizione route
- `lib/state/`: store Redux, reducer e azioni
- `lib/layout/`: app shell responsive e breakpoints
- `lib/pages/welcome/`: splash, welcome, login, registrazione
- `lib/pages/protected/`: area autenticata, corsi e amministrazione
- `lib/api/`: accesso a Firestore per utenti e corsi
- `lib/services/`: OneSignal (mobile + web), notifiche, email templates
- `lib/utils/`: regole di business e helper
- `test/`: test Flutter (iscrizioni, waitlist, preferenze, template)
- `functions/`: Cloud Functions TypeScript (proxy OneSignal)
- `web/`: service worker OneSignal + bridge JS

## Avvio locale

```bash
flutter pub get
flutter run -d chrome
```

## Verifiche utili

```bash
# Flutter
flutter test
flutter analyze
flutter format --set-exit-if-changed .
flutter build web --debug

# Cloud Functions
cd functions
npm test
npm run build
```

## Cloud Functions

Il progetto include una Cloud Function che funge da proxy sicuro verso OneSignal per push ed email. La REST API key non viene mai esposta al client.

Setup iniziale (una volta sola):

```bash
firebase login
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
firebase deploy --only functions
```

Richiede il piano Firebase Blaze.

## Note operative

- La localizzazione principale e italiana (`it_IT`).
- La logica piu sensibile e in `lib/api/courses/`, `lib/utils/course_unsubscribe_helper.dart` e `lib/services/notification_service.dart`.
- La CI valida test, analisi, formattazione e build web.
- Le notifiche email richiedono deploy della Cloud Function con secret configurato.
