# Performance di avvio

Baseline e risultati del lavoro "velocizzare il caricamento dell'app" (Fasi 0–3).
Scenari:

- **S1** visitatore non loggato, avvio a freddo → Welcome
- **S2** socio già loggato, reload → Home con le card
- **S3** login esplicito → Home
- **S4** ritorno alla tab / resume

## Bundle (`flutter build web --wasm --release`, Flutter 3.41.6)

| File | Prima raw | Prima gzip -9 | Dopo raw | Dopo gzip -9 |
|---|---:|---:|---:|---:|
| `main.dart.wasm` | 3.450.162 | 1.249.362 | _da misurare_ | _da misurare_ |
| `main.dart.mjs` | 728.679 | 152.128 | _da misurare_ | _da misurare_ |
| `main.dart.js` (fallback dart2js) | 4.296.458 | 1.075.697 | _da misurare_ | _da misurare_ |
| logo splash HTML | 19.196 (`new_logo_only.png`) | — | _da misurare_ | — |

`skwasm.wasm` (~1,5 MB gzip) arriva da `www.gstatic.com` ed è fuori dal nostro controllo.

## Lavoro per scenario (da codice, verificato su emulatore)

| Scenario | Prima | Dopo |
|---|---|---|
| S1 | splash Flutter fisso 2 s; parse completo tz (`latest.dart`) e symbols intl di tutte le lingue prima di `runApp`; SDK OneSignal scaricato | _da compilare_ |
| S2 | splash 2 s; `Protected` con body vuoto; corsi ×2 (`Protected` + `HomePage`); `getTrainers` = lettura **completa** di `users` | _da compilare_ |
| S3 | `getUserData` → loader spento → callable `grantSignupTrial` (sempre) → `getUserData` → `getUsers` completo in background → corsi ×2 + `getTrainers` completo | _da compilare_ |
| S4 | `notifyRefresh` ×3 (due dalle `invalidateUsersWithExpiring*`, uno da `_onResumeRefresh`): ogni `CoursePreviewCard` ripete la query 3 volte | _da compilare_ |

## Staging, prima (build `develop` @ 7de46754, admin `dev_admin`, cache HTTP calda)

Waterfall S2 da `performance.getEntriesByType('resource')`, ms dalla navigazione:

| Risorsa | Inizio | Fine |
|---|---:|---:|
| `skwasm.wasm` (gstatic) | 79 | 914 |
| `main.dart.wasm` | 955 | 972 |
| Firebase JS SDK (4 moduli) | 1228 | 1283 |
| `accounts:lookup` (ripristino sessione) | 1494 | 1824 |
| logo dello splash Flutter | 1879 | 1888 |
| primo `Listen/channel` Firestore | 11323 | — |

Osservazioni:

- Il console log `… logged` compare **due volte** per reload: `Protected` viene montato due volte.
- Su staging OneSignal non viene inizializzato ma il SDK viene comunque scaricato e
  `login` fallisce in console (`Cannot read properties of undefined`).
- Il salto di ~9,5 s tra splash e prima richiesta Firestore non è attribuibile con certezza
  all'app: sotto il debugger di Chrome MCP il long polling auto-detect di Firestore può
  rallentare. Da riverificare senza strumentazione.
- S3 non misurato su staging (il browser di misura aveva già una sessione admin): il
  confronto S3 è fatto su emulatore.
