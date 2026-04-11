# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `AGENTS.md`.

## Comandi

```bash
flutter pub get          # installa dipendenze
flutter test             # esegui tutti i test
flutter analyze          # analisi statica
flutter format --set-exit-if-changed .  # check formattazione
flutter build web --debug               # build web
flutter run -d chrome                   # avvio locale
```

Dopo ogni modifica, esegui almeno `flutter test` e `flutter analyze`.

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

## Struttura rapida

- Entry point: `lib/main.dart`
- Route: `lib/router.dart` (7 route statiche)
- Stato: `lib/state/` (Redux con thunk)
- Pagine: `lib/pages/welcome/` (auth) e `lib/pages/protected/` (area protetta)
- API Firestore: `lib/api/` (authentication + courses)
- Modelli: `lib/types/fitropeUser.dart`, `lib/types/course.dart`
- Layout responsive: `lib/layout/` (breakpoints + AppShell)
