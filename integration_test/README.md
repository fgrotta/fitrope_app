# Test E2E (integration_test)

Test end-to-end che lanciano l'app **reale** e cliccano davvero, eseguiti
**contro l'ambiente di PRODUZIONE** usando utenti di test dedicati.
Non c'è emulatore: i corsi vengono **creati durante il test** e **eliminati** in
tearDown, e i test che mutano dati si ripuliscono da soli.

## Struttura

```
integration_test/
├── test_env.example.json   # template credenziali (committato)
├── test_env.json           # credenziali reali (gitignored — crealo tu)
├── fixtures/
│   └── test_users.dart      # 2 utenti, 1 trainer, 1 admin (da env)
├── helpers/
│   ├── test_app.dart        # avvio app + gestione splash + attese su rete reale
│   ├── actions.dart         # azioni riusabili: login(), ...
│   └── seed.dart            # crea/elimina corso "Test" (Ferragosto) + lookup trainer
└── flows/
    ├── login_test.dart                # ✅ pronto
    ├── subscribe_to_course_test.dart  # iscrizione (skip finché non validato)
    └── waitlist_swap_test.dart        # waitlist + scambio posto (skip finché non validato)
```

## Scenari

- **login_test** — login valido / credenziali errate.
- **subscribe_to_course_test** — un utente base si prenota a un corso.
- **waitlist_swap_test** — corso da 1 posto: Utente 1 si iscrive, Utente 2 va in
  lista d'attesa, l'Admin li vede, Utente 1 si disiscrive, Utente 2 prende il
  posto liberato e l'Admin vede la lista d'attesa vuota.

> Gli scenari che iscrivono utenti sono `skip: true` finché non vengono
> eseguiti e validati la prima volta (servono Chrome + credenziali reali).
> Richiedono inoltre che gli utenti di test abbiano un **abbonamento attivo con
> entrate disponibili**.

## Credenziali in un file env (niente più password ad ogni run)

1. Copia il template:
   ```bash
   cp integration_test/test_env.example.json integration_test/test_env.json
   ```
2. Compila `test_env.json` con gli account reali (email + password):
   - 2 utenti normali → `TEST_USER1_*`, `TEST_USER2_*`
   - 1 trainer → `TEST_TRAINER_*` (`TEST_TRAINER_NAME` di default `Francesco Trainer`)
   - 1 admin → `TEST_ADMIN_*`

   Tutti gli account devono avere **email verificata** e **account attivo**.
   `test_env.json` è in `.gitignore`: non finisce nel repo.

## Eseguire i test

```bash
flutter pub get

# Tutti gli scenari (le credenziali arrivano dal file env)
flutter test integration_test -d chrome \
  --dart-define-from-file=integration_test/test_env.json

# Singolo scenario
flutter test integration_test/flows/login_test.dart -d chrome \
  --dart-define-from-file=integration_test/test_env.json
```

> Su `-d chrome` serve Chrome installato. In CI si usa `flutter drive` con
> chromedriver; lo aggiungiamo quando colleghiamo la pipeline.

## Corsi di test: creati al volo

Non servono corsi predisposti a mano. `helpers/seed.dart` espone:

- `createFerragostoTestCourse(trainerId: ...)` → crea un corso **"Test"** nella
  **settimana di Ferragosto** (15 agosto, anno corrente o successivo se già
  passato), assegnato al trainer. `reminderEnabled` è **false** di default per
  non far partire promemoria reali in produzione.
- `resolveUserIdByEmail(email)` → ricava l'uid del trainer dall'email.
- `deleteTestCourse(courseId)` → cleanup (da usare in `addTearDown`).

La creazione/eliminazione richiede permessi di scrittura sui corsi: nei test si
fa **login come Admin** prima di creare il corso.

## ⚠️ Attenzione (ambiente di produzione)

- I test toccano dati **veri**: gli scenari che creano corsi/iscrizioni
  **devono eliminarli** in `tearDown` (già previsto via `addTearDown`).
- L'iscrizione/waitlist può inviare email/notifiche reali via OneSignal. Il
  corso di test nasce con `reminderEnabled: false`; valuta i flag con cautela.
- Non cancellare gli utenti di test referenziati in `test_env.json`.

Quando vorrai isolare tutto, il passo successivo è l'emulatore Firebase (punto 1
del piano): seed e cleanup diventano automatici e senza rischi sul DB reale.
