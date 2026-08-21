# Test E2E Flutter

La suite avvia l'app reale in Chrome e accetta soltanto due target sicuri:
Firebase Emulator Suite oppure il progetto staging. Una build senza
`USE_EMULATOR=true` o `APP_ENV=staging` fallisce prima di inizializzare
Firebase; la produzione non è mai un ambiente di test.

## Scenari critici

- `login_test.dart`: login valido/errato, account disattivato, persistenza
  sessione e logout.
- `role_navigation_test.dart`: destinazioni per ruolo e route gestionale
  protetta.
- `subscribe_to_course_test.dart`: creazione Admin, iscrizione e cleanup.
- `waitlist_swap_test.dart`: join, uscita del primo membro e swap atomico.
- `course_management_test.dart`: creazione singola e serie ricorrente via UI.
- `registration_unverified_test.dart`: validazioni, creazione prova e blocco
  email non verificata.
- `registration_verified_login_test.dart`: seconda fase dopo verifica Admin SDK.

Il driver è `test_driver/integration_test.dart`. Sul web si usa un solo target
per invocazione con chromedriver sulla porta 4444.

## Emulatore

```bash
cd functions && npm ci && npm run build && cd ..
printf "ONESIGNAL_REST_API_KEY=emulator-dummy-key\n" > functions/.secret.local
firebase emulators:start --project fit-rope-app-1f575
cd functions && npm run seed:emulator && cd ..
chromedriver --port=4444

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/login_test.dart \
  -d chrome \
  --dart-define=USE_EMULATOR=true \
  --dart-define=TEST_RUN_NAMESPACE=manuale \
  --dart-define-from-file=integration_test/test_env.emulator.json
```

Il project ID è obbligatorio e deve combaciare con la configurazione Flutter e
con `seedEmulator.js`. Le fixture includono anche un account disattivato per il
fail-closed del login. OneSignal è disabilitato dal bootstrap E2E.

## Staging

Generare un file gitignored `test_env.staging.json` dal template, usando solo
gli account `stg_*`, e passare `APP_ENV=staging`, tutti i define `FIREBASE_*`
richiesti e un `TEST_RUN_NAMESPACE` univoco.

Il workflow staging esegue la suite dopo il deploy delle rules. Prima e dopo il
run usa `functions/scripts/e2eAdmin.js` per eliminare risorse abbandonate.

## Registrazione bifase

Il primo drive riceve `SIGNUP_TEST_EMAIL` e `SIGNUP_TEST_PASSWORD`. Poi il
runner host verifica lo stesso account:

```bash
npm --prefix functions run e2e:admin -- verify-signup \
  --email "$SIGNUP_TEST_EMAIL" --emulator
```

Il secondo drive verifica il login; `delete-signup` viene sempre eseguito nel
cleanup. I corsi hanno nomi `[TEST:<namespace>] ...`, data otto giorni avanti
alle 18:00 Europe/Rome e vengono eliminati tramite la callable Admin
`deleteCourse`, preservando rimborsi e ledger anche dopo un run interrotto.

Per architettura, catalogo e limiti vedere `docs/AREE_DI_TEST.md`.
