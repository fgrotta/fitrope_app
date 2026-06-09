# FitRope

FitRope e una applicazione Flutter per la gestione di utenti, autenticazione e iscrizioni ai corsi fitness. Nel codice UI il brand esposto e `Fit House`, mentre il package del progetto resta `fitrope_app`.

## Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Cloud Functions (TypeScript, proxy verso OneSignal)
- OneSignal (push mobile native + email server-side). Push web disabilitate.
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
- per ogni corso, l'admin puo abilitare/disabilitare singolarmente promemoria e lista d'attesa
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
- `web/`: index.html e asset web (OneSignal Web SDK commentato/disabilitato)

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

### Setup iniziale (una volta sola)

Richiede il piano Firebase **Blaze**.

```bash
# 1. Login
firebase login

# 2. Imposta il secret della REST API Key OneSignal
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
# Incolla la chiave os_v2_app_... quando richiesto

# 3. Primo deploy
firebase deploy --only functions
```

Se il primo deploy fallisce con errore di permessi IAM sul build service account, assegna i ruoli necessari al compute service account (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`):

```bash
PROJECT_ID="fit-rope-app-1f575"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/logging.logWriter"
```

### Aggiornare la function

Ogni volta che modifichi il codice in `functions/`:

```bash
# 1. (opzionale) verifica locale
cd functions
npm test
npm run build
cd ..

# 2. Deploy (il predeploy compila automaticamente)
firebase deploy --only functions
```

### Aggiornare il secret OneSignal

Se cambi la REST API Key:

```bash
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
# Dopo l'aggiornamento serve un re-deploy per bindare il nuovo valore
firebase deploy --only functions
```

### Vedere i log runtime

```bash
firebase functions:log                           # tutti i log
firebase functions:log --only sendOneSignalNotification   # solo una function
```

Oppure dalla [console Cloud Functions](https://console.cloud.google.com/functions/list?project=fit-rope-app-1f575).

### Rollback o eliminazione

```bash
# Elimina la function (il client smetterà di funzionare finché non riesegui il deploy)
firebase functions:delete sendOneSignalNotification
```

Per un rollback pulito, fai commit del codice precedente e riesegui `firebase deploy --only functions`.

## Note operative

- La localizzazione principale e italiana (`it_IT`).
- La logica piu sensibile e in `lib/api/courses/`, `lib/utils/course_unsubscribe_helper.dart` e `lib/services/notification_service.dart`.
- La CI valida test, analisi, formattazione e build web.
- Le notifiche email richiedono deploy della Cloud Function con secret configurato.
