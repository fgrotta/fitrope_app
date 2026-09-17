# Test E2E (integration_test)

La suite E2E unica (`e2e_test.dart`) avvia l'app Flutter reale e usa Firebase
Emulator Suite in locale oppure il progetto Firebase staging. Le fixture sono
create dal control plane Admin SDK, mai dall'app, e vengono eliminate al termine
del run.

## Scenari coperti

- registrazione self-service: account Auth, documento utente con
  `ABBONAMENTO_PROVA` e invio della verifica email;
- abbonamento v2: iscrizione e disiscrizione a un corso futuro;
- lista d'attesa: ingresso, conferma, rilascio del posto e subentro;
- pacchetto legacy: consumo e rimborso di un ingresso.

Il control plane verifica anche lo stato finale di corsi, `courses`, contatori,
`waitlist`, snapshot `activeSubscriptions` e ricevute di notifica (emulatore o
staging). Gli account e gli ID sono sintetici e prefissati `e2e_` o `stg_e2e_`.

## Prerequisiti

- Flutter 3.41.6 (o versione compatibile con `pubspec.yaml`);
- Node.js e dipendenze Functions (`cd functions && npm ci`);
- `firebase-tools@15` e Java 21+;
- Chrome e ChromeDriver della stessa major version (`chromedriver --version`);
- per staging: ADC/OIDC con permessi Admin SDK e i valori Firebase staging.

Il binario ChromeDriver può essere aggiunto al PATH per la sola sessione:

```bash
export PATH="/percorso/alla/cartella/chromedriver:$PATH"
chromedriver --version
```

## E2E locale su emulatori (comando consigliato)

Lo script compila le Functions, avvia Auth/Firestore/Functions emulator, crea
le fixture, attende ChromeDriver, esegue `flutter drive`, verifica il backend e
pulisce processi e dati:

```bash
export PATH="/usr/local/opt/openjdk@21/bin:$PATH"   # se necessario su macOS
scripts/e2e.sh emulator
```

Per Apple Silicon il JDK può essere in
`/opt/homebrew/opt/openjdk@21/bin`. L'Emulator UI è disponibile su
`http://127.0.0.1:14000` durante il run. Il manifest temporaneo è
`integration_test/e2e_manifest.json` (gitignored).

## E2E su staging

Il progetto deve essere quello staging e il control plane deve poter usare ADC:

```bash
export E2E_PROJECT_ID=fit-rope-staging
export GOOGLE_APPLICATION_CREDENTIALS=/percorso/service-account.json
export FIREBASE_API_KEY=...
export FIREBASE_APP_ID=...
export FIREBASE_MESSAGING_SENDER_ID=...
export FIREBASE_PROJECT_ID="$E2E_PROJECT_ID"
export FIREBASE_AUTH_DOMAIN="${E2E_PROJECT_ID}.firebaseapp.com"
export FIREBASE_STORAGE_BUCKET=...
export FIREBASE_MEASUREMENT_ID=...
scripts/e2e.sh staging
```

Lo staging richiede anche Functions e Rules già deployate. In GitHub Actions il
job `e2e` di `.github/workflows/staging.yml` prepara automaticamente ADC,
ChromeDriver, manifest e cleanup; il job è serializzato dopo `deploy-rules`.

## Test Flutter e Functions senza E2E

```bash
flutter analyze --no-fatal-infos
flutter test                         # test Dart
cd functions && npm test -- --runInBand
npm run test:integration              # Functions contro emulatori reali
```

## Diagnostica e cleanup

I log locali sono `.context/e2e-emulator.log` e
`.context/e2e-chromedriver.log`. Se un run viene interrotto, lo script termina
l'albero dei processi al successivo `EXIT`; in caso di processi già rimasti
attivi, individuarli con:

```bash
ps ax -o pid=,command= | grep -E 'firebase.*emulators:start|chromedriver --port=4444' | grep -v grep
```

Chiudere solo i PID E2E individuati, quindi rilanciare lo script. Non eseguire
la suite contro produzione: i test che mutano dati sono esclusivamente
emulatore o staging.
