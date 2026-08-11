# FitRope App - Guida al Deployment

## Workflow CI/CD

Questo progetto utilizza GitHub Actions per automatizzare il processo di build e deployment.

### Branch e Workflow

#### Pull Request verso `main` e `develop`
- **Workflow**: `ci.yml`
- **Azioni**: Test, analisi del codice, controllo formattazione, build di test
- **Trigger**: Pull Request e avvio manuale

#### Branch `develop`
- **Workflow**: `staging.yml`
- **Azioni**: Test completi, build web staging, deploy Functions + seed, deploy GitHub Pages, deploy Firestore Rules, smoke test
- **Trigger**: Push e avvio manuale

#### Branch `release`
- **Workflow**: `release.yml`
- **Azioni**: **Solo validazione** — test, analisi, formattazione, build web wasm, test Functions unit e integrazione
- **Trigger**: Push e Pull Request

### Processo di Release

1. **Sviluppo**: feature branch, PR verso `develop`
2. **Test PR**: ogni Pull Request verso `main` o `develop` attiva `ci.yml`
3. **Staging**: ogni merge/push su `develop` attiva `staging.yml`, che testa **e deploya** l'ambiente staging (vedi sotto)
4. **Release in produzione**: il branch `release` esegue solo i gate di validazione. **Il deploy in produzione è manuale**: `flutter build web --wasm --release` e upload di `build/web` sull'hosting Hostinger. Le Cloud Functions di produzione si deployano con `firebase deploy --project prod --only functions`.

### Ambiente Staging

Progetto Firebase separato (`fit-rope-staging`), sito su GitHub Pages, tutto automatico su `develop`.

- **URL**: https://fgrotta.github.io/fitrope_app/
- **Ordine dei job — vincolante**: `deploy-functions` (+ seed) → `deploy-pages` → `deploy-rules` → `smoke-test`. Le callable devono esistere prima della web nuova; le rules vanno per ultime perché bloccano le scritture dirette del client e uscendo prima romperebbero i client sulla build vecchia.
- **Autenticazione**: OIDC / Workload Identity Federation, nessuna service-account key nel repo. Vars richieste nell'environment GitHub `staging`: `FIREBASE_STAGING_*`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_STAGING_DEPLOY_SERVICE_ACCOUNT`, `ONESIGNAL_APP_ID`, `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`.
- **Smoke test**: verifica che il sito risponda (`index.html`, `version.json`, `flutter_bootstrap.js`) e che tutte le callable enrollment esistano davvero sul progetto staging.
- **Concurrency**: `staging-deploy` con `cancel-in-progress` — un push nuovo annulla il deploy in corso.
- **Dati**: solo sintetici, creati da `functions/scripts/seedStaging.js`. Mai copiare dati reali in staging.

### Build Output

#### Web
- **Directory**: `build/web`
- **Produzione**: https://app.fithousemonza.it — Hostinger, upload **manuale** di `build/web`
- **Staging**: https://fgrotta.github.io/fitrope_app/ — GitHub Pages tramite branch `gh-pages`, automatico da `develop`

### Configurazione Locale

Per eseguire build locali:

```bash
# Installazione dipendenze
flutter pub get

# Test
flutter test

# Analisi (come la CI: gli info restano visibili ma non bloccano)
flutter analyze --no-fatal-infos

# Formattazione (gate della CI)
dart format --set-exit-if-changed .

# Build Web — --wasm è il path usato da CI e produzione
flutter build web --wasm --release

# Cloud Functions
cd functions && npm ci && npm run build && npm test
npm run test:integration   # richiede Java 21 nel PATH
```

### Dependabot

Il progetto utilizza Dependabot per:
- Aggiornamenti automatici delle dipendenze Dart/Flutter
- Aggiornamenti delle GitHub Actions
- Pull Request automatici ogni lunedì alle 9:00

### Troubleshooting

#### Build Fallite
1. Verificare che tutti i test passino localmente (`flutter test` e `cd functions && npm test`)
2. Controllare la formattazione del codice: `dart format --set-exit-if-changed .`
3. Verificare le dipendenze: `flutter pub deps`

#### Deploy staging fallito
1. `deploy-functions` in errore su vars vuote: il job deve avere `environment: staging` e dichiarare `STAGING_PROJECT_ID` nel proprio blocco `env` — su questo workflow la variabile è per job, non a livello di workflow.
2. `smoke-test` che segnala una callable mancante: il deploy Functions è andato solo in parte, ri-lanciare il workflow (`workflow_dispatch`) prima di considerare staging usabile.
3. Errori di autenticazione: controllare `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_STAGING_DEPLOY_SERVICE_ACCOUNT` nell'environment `staging` e che il job abbia `permissions: id-token: write`.

### Contatti

Per problemi relativi al deployment, contattare il team di sviluppo. 
