# Ambienti di test — analisi e decisione

> Analisi del 2026-06-10 (post-PR4). Contesto: fino a PR4 ogni prova manuale
> avveniva direttamente in produzione (`fit-rope-app-1f575`), con gate
> `kDebugMode` e DebugEmailPage come uniche protezioni. Con il write-path
> iscrizioni server-side (PR4) — crediti reali, email reali — non è più
> sostenibile.

## Stato di partenza

- **Un solo progetto Firebase** = produzione. Nessun alias in `.firebaserc`,
  nessuna config emulatori, `main.dart` punta sempre a prod.
- Copertura esistente: unit test (Dart su logica display/serializzazione, Jest
  su logica pura + handler con fake Firestore in-memory). Nessun test
  d'integrazione reale, nessun ambiente isolato.

## Opzioni valutate

### A. Firebase Emulator Suite (locale) — ✅ IMPLEMENTATA

Auth + Firestore + Functions girano in locale; l'app Flutter si collega con
`--dart-define=USE_EMULATOR=true`.

- **Copre**: flussi end-to-end reali (callable vere, transazioni vere,
  concorrenza multi-utente), Emulator UI per ispezionare i dati, test delle
  `firestore.rules` (da PR6), base per i test d'integrazione in CI.
- **Non copre**: OneSignal/email reali (key fittizia in `functions/.secret.local`
  → invii falliscono con warning nel log, il codice è best-effort), push native,
  **indici Firestore** (l'emulatore non li richiede: una query che in prod esige
  un indice composito qui passa comunque), comportamento Cloud Run reale
  (cold start, IAM).
- **Costo**: zero. **Prerequisiti**: `firebase-tools` + Java 21+ (richiesto da
  firebase-tools 15.x).
- Istruzioni operative: vedi "Come testare in locale" più sotto.

### B. Test d'integrazione su emulatore in CI — pianificata (PR5)

`firebase emulators:exec` + Jest contro le callable nell'emulatore: transazioni
a 3 documenti, atomicità, concorrenza/capienza, retry. È la **categoria C** del
piano (§8), da consegnare in PR5. Diventa la rete di regressione permanente del
write-path.

### C. Progetto Firebase di staging — ⭐ TARGET (la migliore, da fare prima del rilascio)

Progetto gemello `fit-rope-staging`(-like): Auth, Firestore, Functions
deployate, dati sintetici, seconda app OneSignal.

- **Copre in più di A/B**: deploy reale (predeploy, secrets, region, IAM),
  **indici veri**, prove da telefono/browser di chiunque, prova generale del
  vincolo di deploy functions→web, notifiche email/push vere senza toccare
  utenti reali.
- **Prerequisiti / lavoro necessario**:
  - Creazione progetto + **piano Blaze** (functions v2): serve il billing
    account (riusabile quello di prod), costo ~0€ ai volumi di test, budget
    alert consigliato. ⚠️ Richiede azione di Francesco (account/billing).
  - Parametrizzare `ONESIGNAL_APP_ID` (oggi hardcoded in
    `functions/src/handler.ts` e `lib/main.dart`) + seconda app OneSignal.
  - `flutterfire configure --project=<staging>` → secondo `firebase_options`,
    switch client via `--dart-define=ENV=staging`.
  - Alias in `.firebaserc` (`firebase use staging|default`).
  - La web di staging NON va pubblicata sul GitHub Pages di prod.
  - **GDPR**: mai copiare dati reali (nomi/email/telefoni) in staging — seed
    sintetico o export anonimizzato.
- **Quando**: prima di rilasciare in produzione il blocco PR3–PR6.

### Scartate

- **Dati di test in produzione** (status quo pre-analisi): nessun isolamento,
  crediti/email reali a rischio, impossibile testare le rules. Abbandonata.
- **Database Firestore multipli nello stesso progetto**: Auth e Functions
  restano condivisi, il codice andrebbe parametrizzato sul `databaseId` —
  complessità da mezza misura, non vale rispetto a C.

## Decisione (2026-06-10)

| Strato | Stato | Quando |
|---|---|---|
| **A. Emulatore locale** | ✅ implementata | da subito, per sviluppo e QA manuale |
| **B. Emulatore in CI (categoria C)** | pianificata | dentro PR5 |
| **C. Staging** | ⭐ target, decisa come opzione migliore | prima del rilascio in prod del blocco PR3–PR6 (serve creazione progetto/billing da parte di Francesco) |

**Regola operativa**: niente arriva in produzione senza essere passato
dall'emulatore (sempre) e da staging (per i rilasci che toccano l'area
iscrizioni). La produzione non è un ambiente di test.

---

## Come testare in locale (opzione A)

### Prerequisiti (una tantum)

- `firebase-tools` (`npm i -g firebase-tools`) e login (`firebase login`)
- **Java 21+** (richiesto da firebase-tools 15.x per l'emulatore Firestore).
  Sul Mac di sviluppo `openjdk@21` è già installato via Homebrew ma keg-only:
  il `java` nel PATH è il 17 → anteporre il 21 quando si avviano gli emulatori
  (vedi sotto) o aggiornare il PATH in `~/.zshrc`
  (`export PATH="/usr/local/opt/openjdk@21/bin:$PATH"`).
- `cd functions && npm install && npm run build`
- Creare `functions/.secret.local` (gitignored) con una key fittizia, così le
  functions non toccano OneSignal reale:

  ```
  ONESIGNAL_REST_API_KEY=emulator-dummy-key
  ```

### Avvio

```bash
# 1. Compila le functions e avvia gli emulatori (Auth, Firestore, Functions + UI)
cd functions && npm run build && cd ..
PATH="/usr/local/opt/openjdk@21/bin:$PATH" firebase emulators:start

# 2. (in un altro terminale) Popola dati sintetici: utenti, corsi, abbonamenti
cd functions && npm run seed:emulator

# 3. Avvia l'app contro gli emulatori
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

- Emulator UI: <http://localhost:4000> (ispezione documenti, utenti Auth, log functions)
- Utenti seed (password `test1234`): vedi `functions/scripts/seedEmulator.js`
  (admin, trainer, utente legacy a pacchetto, utente legacy temporale, utente
  nuovo modello con abbonamenti)
- Da device fisico sulla LAN: `--dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=<IP del Mac>`
  (gli emulatori ascoltano su `0.0.0.0`, vedi `firebase.json`)

### Cosa ricordare

- I dati sono effimeri: si riparte puliti a ogni avvio (ri-eseguire il seed).
  Per conservare uno scenario: `firebase emulators:export ./.emulator-data` e
  riavvio con `firebase emulators:start --import ./.emulator-data`.
- Le email/push NON partono (key fittizia): l'esito si verifica nei log delle
  functions nella Emulator UI.
- L'emulatore **non valida gli indici Firestore**: prima del deploy in prod di
  query nuove con filtri compositi, verificare gli indici (staging li copre).
- Il runtime dell'emulatore functions monkey-patcha `firebase-admin`: il
  namespace `admin.firestore` PERDE le proprietà statiche (`Timestamp`,
  `FieldValue`). Nel codice delle functions usare **sempre gli import modulari**
  `import { Timestamp, FieldValue } from "firebase-admin/firestore"` — la
  regola è blindata dal test `functions/src/__tests__/conventions.test.ts`.
- **Esposizione LAN**: gli emulatori ascoltano su `0.0.0.0` (scelta deliberata
  per il test da device fisico) → mentre girano, chiunque sulla stessa rete
  può leggere/scrivere i dati emulati e invocare le functions. Accettabile
  perché i dati sono sintetici ed effimeri; su reti non fidate cambiare gli
  host in `localhost` in `firebase.json`.

### Smoke test eseguito al setup (2026-06-10)

Verificato end-to-end sull'emulatore: login Auth (`pacchetto@test.it`) →
`subscribeToCourse` ok (entrate 5→4, `enrollmentConsumption` scritto,
`subscribed` 0→1) → doppia iscrizione rifiutata (`ALREADY_EXISTS`) →
`unsubscribeFromCourse` ok (rimborso 4→5, registro ripulito). Il primo run ha
trovato un bug reale invisibile agli unit test (`admin.firestore.Timestamp`
undefined nel runtime emulato, vedi sopra) — corretto con gli import modulari.
