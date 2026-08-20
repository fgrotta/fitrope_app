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
│   └── seed.dart            # crea/elimina il corso di test (Ferragosto) + lookup trainer
├── login_test.dart                # ✅ pronto (non skippato)
├── subscribe_to_course_test.dart  # iscrizione (skip: true finché non validato)
└── waitlist_swap_test.dart        # waitlist + scambio posto (skip: true finché non validato)
```

Il driver per l'esecuzione via `flutter drive` esiste già:
`test_driver/integration_test.dart` (`integrationDriver()`).

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

Su target **web** gli `integration_test` non girano con `flutter test -d chrome`:
serve `flutter drive` con chromedriver in ascolto.

```bash
flutter pub get

# 1. chromedriver in ascolto (versione allineata al Chrome installato)
chromedriver --port=4444

# 2. Un singolo scenario (le credenziali arrivano dal file env)
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/login_test.dart \
  -d chrome \
  --dart-define-from-file=integration_test/test_env.json
```

> Nessun workflow CI esegue ancora questa suite (vedi TODO in `CLAUDE.md`).

## Corsi di test: creati al volo

Non servono corsi predisposti a mano. `helpers/seed.dart` espone:

- `createFerragostoTestCourse(trainerId: ...)` → crea un corso di test nella
  **settimana di Ferragosto** (`ferragostoSlot`: 15 agosto, anno corrente o
  successivo se già passato), assegnato al trainer, con nome generato da
  `buildTestCourseName(...)`. `reminderEnabled` è **false** di default per non
  far partire promemoria reali in produzione.
- `resolveUserIdByEmail(email)` / `resolveUserNameByEmail(email)` → lookup del
  trainer dall'email.
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
