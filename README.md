# FitRope

FitRope e una applicazione Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Nel codice UI il brand esposto e `Fit House`, mentre il package del progetto resta `fitrope_app`.

## Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Redux + `flutter_redux`
- `flutter_design_system` come dipendenza Git esterna

## Funzionalita principali

- login, registrazione, reset password e verifica email
- area protetta con navigazione responsive tra home, calendario e strumenti admin
- gestione corsi e corsi ricorrenti
- regole di iscrizione/disiscrizione basate su ruolo e tipologia di abbonamento
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
- `lib/utils/`: regole di business e helper
- `test/`: test sulle regole di iscrizione e disiscrizione

## Avvio locale

```bash
flutter pub get
flutter run -d chrome
```

## Verifiche utili

```bash
flutter test
flutter analyze
flutter format --set-exit-if-changed .
flutter build web --debug
```

## Note operative

- La localizzazione principale e italiana (`it_IT`).
- La logica piu sensibile e in `lib/api/courses/` e `lib/utils/course_unsubscribe_helper.dart`.
- La CI valida test, analisi, formattazione e build web.
