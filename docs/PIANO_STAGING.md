# Piano ambiente staging

## Obiettivo

Realizzare un ambiente staging completo e ripetibile:

- frontend Flutter Web su GitHub Pages;
- Cloud Functions Firebase dedicate;
- Auth e Firestore segregati dalla produzione;
- notifiche OneSignal testabili senza raggiungere utenti reali;
- deploy automatico dal branch `develop` dopo i test.

La produzione resta `https://app.fithousemonza.it` su Hostinger, con deploy manuale.

## Decisioni architetturali

| Area | Decisione |
| --- | --- |
| Firebase | Nuovo progetto Firebase staging, separato dalla produzione |
| Database | Firestore default database del progetto staging |
| Auth | Firebase Auth del progetto staging |
| Functions | Stesso codice, deploy sul progetto staging in `europe-west8` |
| Hosting staging | GitHub Pages |
| Branch staging | `develop` |
| OneSignal | Stessa app e stesse credenziali della produzione, con guardrail staging |
| Produzione | Hostinger, deploy manuale |

Un progetto Firebase separato isola Firestore, Auth, Functions, Secret Manager, quote e IAM. Collezioni prefissate nello stesso progetto non garantiscono questa separazione.

## Prerequisiti cloud

1. Creare il progetto Firebase/GCP staging, per esempio `fit-rope-staging`, con piano Blaze.
2. Creare Firestore Native mode, Firebase Auth e Cloud Functions in `europe-west8`.
3. Aggiungere il dominio GitHub Pages agli authorized domains di Firebase Auth.
4. Configurare Workload Identity Federation GitHub-Google per il deploy CI. Non usare chiavi JSON persistenti.
5. Creare GitHub Environment `staging`, con protezione deploy e variabili necessarie.
6. Confermare il repository GitHub canonico per Pages. Il remoto corrente e `fgrotta/fitrope_app`, mentre documentazione storica cita `dellarosamarco/fitrope_app`.
7. Creare e proteggere il branch `develop`: non esiste ancora nel repository e il workflow staging si attiva solo dai suoi push.

## Modifiche repository

### Firebase CLI

Aggiornare `.firebaserc` con alias espliciti:

```json
{
  "projects": {
    "prod": "fit-rope-app-1f575",
    "staging": "fit-rope-staging"
  }
}
```

Ogni deploy deve indicare alias o `--project`; non deve dipendere da `default`.

Parametrizzare lo script seed: oggi punta al project ID produzione e deve ricevere il project staging in modo esplicito.

### Flutter

1. Generare FirebaseOptions separate per produzione e staging.
2. Introdurre `APP_ENV` tramite `--dart-define`, con valori `prod` e `staging`.
3. Selezionare le FirebaseOptions corrette in `Firebase.initializeApp`.
4. Rendere obbligatorio `--dart-define=APP_ENV=staging` nella build Pages.
5. Mostrare un indicatore discreto `STAGING` solo nelle build staging.

### Functions e OneSignal

Functions staging usa lo stesso `ONESIGNAL_APP_ID` e lo stesso `ONESIGNAL_REST_API_KEY` della produzione. I valori vanno impostati anche nel Secret Manager staging, perche i progetti Firebase non condividono secret.

`ONESIGNAL_APP_ID` e parametrizzato tramite la configurazione runtime Functions (`.env.<projectId>`). Il valore resta uguale oggi e puo cambiare senza refactor.

Guardrail obbligatori staging:

- utenti seed solo sintetici, con UID prefissati `stg_` e email dedicate al test;
- allowlist di email test per invii email;
- soggetto e contenuto marcati `[STAGING]`;
- destinatari fuori allowlist soppressi e loggati;
- nessun import di utenti, email o device token produzione;
- push Web resta disabilitato e il backend staging sopprime ogni payload push.

## Configurazione GitHub e Firebase

Il workflow richiede il GitHub Environment `staging` e queste **Actions variables**: `FIREBASE_STAGING_PROJECT_ID`, `FIREBASE_STAGING_API_KEY`, `FIREBASE_STAGING_APP_ID`, `FIREBASE_STAGING_MESSAGING_SENDER_ID`, `FIREBASE_STAGING_AUTH_DOMAIN`, `FIREBASE_STAGING_STORAGE_BUCKET`, `FIREBASE_STAGING_MEASUREMENT_ID` (opzionale), `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_STAGING_DEPLOY_SERVICE_ACCOUNT`, `ONESIGNAL_APP_ID`, `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`.

Prima del primo deploy impostare nel Secret Manager del **progetto staging** la stessa chiave usata in produzione:

```bash
firebase functions:secrets:set ONESIGNAL_REST_API_KEY --project fit-rope-staging
```

Il file `functions/.env.staging.example` documenta la configurazione runtime per un deploy manuale; il workflow genera il file `.env.<projectId>` senza salvare segreti nel repository. GitHub Pages deve usare come source `GitHub Actions`.

## Workflow GitHub Actions

Creare `staging.yml` con trigger push su `develop` e `workflow_dispatch`.

Ordine dei job:

1. test Flutter, analisi e build Web con `APP_ENV=staging`;
2. build TypeScript e test unitari Functions;
3. test integrazione Emulator;
4. autenticazione Google via OIDC e Workload Identity Federation;
5. deploy Functions staging;
6. seed idempotente di utenti e dati sintetici staging;
7. deploy GitHub Pages;
8. deploy Firestore Rules staging per ultime;
9. smoke test sito e callable staging.

Il deploy dipende da tutti i job test. Aggiungere `concurrency` per annullare deploy staging obsoleti.

Usare `actions/upload-pages-artifact` e `actions/deploy-pages`. Il workflow `release.yml` corrente va trasformato o sostituito: pubblica il sito ma non Functions/rules e tratta Pages come release.

`ci.yml` resta dedicato a PR e `main`, senza credenziali cloud e senza deploy.

### Backlog ottimizzazione pipeline

1. Introdurre caching sui job CI/staging per ridurre build inutili e consumo runner:
   - Flutter: cache SDK Flutter, Pub cache e, se compatibile con la pipeline, artefatti `.dart_tool`/build invalidati dal lockfile.
   - Functions: cache npm basata su `functions/package-lock.json` usando `actions/setup-node` con `cache: npm` e `cache-dependency-path`.
   - Firebase Emulator: evitare install ripetute non necessarie di `firebase-tools` quando possibile, o fissare un caching esplicito del tool.
   - Criterio di accettazione: run successivo senza cambi dipendenze deve mostrare cache hit e tempi ridotti sui job test/build.

2. Aggiornare Node per Functions/tooling a Node 24:
   - aggiornare i job GitHub Actions unit/build Functions a Node 24;
   - mantenere integration test emulatori e deploy Functions su Node 22 per restare allineati al runtime Firebase;
   - mantenere il runtime Firebase esplicito a `nodejs22` in `firebase.json` finche Firebase non supporta ufficialmente Node 24 per Cloud Functions for Firebase;
   - tenere `functions/package.json` compatibile con Node 22 e Node 24 per evitare warning `EBADENGINE` durante i job CI;
   - aggiornare `functions/package.json`/runtime Firebase quando il runtime Functions Node 24 e supportato nel progetto;
   - verificare compatibilita di `firebase-functions`, `firebase-admin`, `ts-jest` e `firebase-tools`.
   - Criterio di accettazione: `npm run build`, `npm test`, `npm run test:integration` e deploy staging verdi con runtime/tooling allineati.

3. Azzerare i warning della pipeline:
   - migrare le Actions che generano warning Node.js 20 deprecation alle versioni che girano nativamente su Node 24;
   - mantenere `actions/setup-java@v5` sui job Emulator Suite;
   - eliminare eventuali warning Firebase CLI, incluso il blocco `flutter` non riconosciuto in `firebase.json` se compare nei log CI/deploy.
   - Criterio di accettazione: run CI e Staging Deploy verdi senza annotations/warning operativi.

## Ordine deploy

1. Functions staging.
2. Seed dati sintetici staging.
3. Web staging GitHub Pages.
4. Firestore Rules staging.

## Seed e smoke test

Il workflow esegue `functions/scripts/seedStaging.js` dopo il deploy Functions. Il seed e idempotente e rifiuta project ID non staging o il progetto produzione noto; crea Admin, Trainer e utente sintetici, corsi Open/Hyrox/PT, abbonamenti a frequenza e ingressi e una waitlist.

Dopo ogni deploy verificare:

1. login staging;
2. assegnazione abbonamento;
3. iscrizione, disiscrizione e waitlist;
4. aggiornamenti Firestore;
5. notifica inviata solo alla allowlist;
6. Firebase project e URL corretti nella build staging.

## Criteri di accettazione

- GitHub Pages serve una build con `APP_ENV=staging`.
- La build comunica solo con Firebase staging.
- Firestore, Auth, Functions e Secret Manager staging non condividono dati con produzione.
- Deploy staging solo dopo test Flutter, unit Functions e Emulator verdi.
- Notifiche staging non raggiungono utenti fuori allowlist.
- Produzione Hostinger resta manuale con `APP_ENV=prod`.

## Sequenza implementazione

1. Confermare repository GitHub canonico e project ID Firebase staging.
2. Creare progetto Firebase/GCP, Auth, Firestore, Workload Identity Federation e Pages environment.
3. Introdurre alias Firebase, FirebaseOptions multi ambiente e seed parametrizzato.
4. Parametrizzare OneSignal e guardrail staging.
5. Creare `staging.yml` e trasformare o rimuovere deploy Pages da `release.yml`.
6. Deploy iniziale manuale guidato su staging.
7. Eseguire smoke test e abilitare deploy automatico da `develop`.
8. Aggiornare runbook operativi.
