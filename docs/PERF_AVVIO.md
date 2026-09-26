# Performance di avvio

Baseline e risultati del lavoro "velocizzare il caricamento dell'app" (Fasi 0–3).
Scenari:

- **S1** visitatore non loggato, avvio a freddo → Welcome
- **S2** socio già loggato, reload → Home
- **S3** login esplicito → Home
- **S4** ritorno alla tab / resume

"Prima" = `develop` @ 7de46754, "dopo" = questo branch.

## Bundle (`flutter build web --wasm --release`, Flutter 3.41.6)

| File | Prima raw | Prima gzip -9 | Dopo raw | Dopo gzip -9 |
|---|---:|---:|---:|---:|
| `main.dart.wasm` | 3.450.162 | 1.249.362 | 3.415.047 | 1.238.721 |
| `main.dart.mjs` | 728.679 | 152.128 | 215.919 | 32.774 |
| `main.dart.js` (fallback dart2js) | 4.296.458 | 1.075.697 | 3.301.420 | 917.678 |
| logo splash HTML | 19.196 (1541×2311) | — | 12.507 (266×400) | — |

Il guadagno sul percorso wasm sta quasi tutto in `main.dart.mjs` (−119 KB gzip): i dati
di timezone e intl finivano lì come stringhe JS. `skwasm.wasm` (~1,5 MB gzip) arriva da
`www.gstatic.com` ed è fuori dal nostro controllo.

## Query Firestore per scenario (emulatore, socio `abbonato@test.it`)

Contate intercettando il log debug del Firestore JS SDK (`setLogLevel('debug')`, righe
`addTarget`) su build release con `USE_EMULATOR=true`, stessa istanza e stesso seed.

| Scenario | Prima | Dopo |
|---|---|---|
| S2 reload | corsi ×1, get profilo, **`users` intera** (getTrainers) | corsi ×1, get profilo, `users where role == Trainer` |
| S3 login socio | get profilo → callable `grantSignupTrial` (~2,2 s sull'emulatore) → get profilo → **`users` intera** → corsi ×2 | get profilo → `users where role == Trainer` (corsi dalla cache) |
| S3 login admin | come sopra | get profilo → `users` intera (serve allo staff) |
| S4 resume | corsi ×2, get profilo ×2 (tre `notifyRefresh`) | corsi ×1, get profilo ×1 |

S3 socio, da `signIn` riuscito a `Protected` montato: prima ~2,2 s di callable prima ancora
di navigare, dopo ~0,23 s.

## Avvio a freddo S1 (build wasm di produzione servite in locale, nessun login)

| | Prima | Dopo |
|---|---|---|
| primo frame Flutter | ~0,45–0,6 s | ~0,47–0,67 s |
| Welcome visibile | ~2,5 s (splash fisso 2 s) | al primo frame |
| richieste OneSignal | 3 | 0 |
| splash HTML | resta nel DOM sotto il canvas, spinner invisibile | rimosso al primo frame, spinner blu |

Per un utente già loggato (S2) i 2 s non si pagavano nemmeno prima: la route iniziale
`/splash` fa costruire anche la Welcome sotto, e la sua `loggedRedirect` sostituiva subito
lo splash. Ora sia `loggedRedirect` sia `SplashScreen` navigano solo se la loro route è in
cima (`isCurrent`): senza, lo splash senza attesa avrebbe spinto un secondo `Protected`
(test `test/splash_screen_test.dart` e `test/logged_redirect_test.dart`).

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

- Il console log `… logged` compare **due volte** per reload su staging: al reload su
  `/#/protected` il Navigator costruisce `['/', '/protected']` e la Welcome sotto chiamava
  `loggedRedirect`, sostituendo il `Protected` appena montato con un secondo (doppio
  `getUserData` e doppio login OneSignal a ogni reload). Sull'emulatore non si vedeva perché
  lì si parte dalla root. Ora `loggedRedirect` agisce solo se la pagina è in cima
  (`test/logged_redirect_test.dart`).
- Su staging OneSignal non viene inizializzato ma il SDK veniva comunque scaricato e
  `login` falliva in console (`Cannot read properties of undefined`). Con il caricamento
  lazy il SDK non viene più richiesto dove OneSignal è spento.
- Il salto di ~9,5 s tra splash e prima richiesta Firestore non è attribuibile con certezza
  all'app: sotto il debugger di Chrome MCP il long polling auto-detect di Firestore può
  rallentare. Da riverificare senza strumentazione.
- La colonna "dopo" su staging si compila dopo il merge su `develop`.

## Decisioni

- **`CoursePreviewCard`** resta con una query per card: nel seed nessun socio ha più di
  una card, e un socio reale ne vede tipicamente ≤ 3 (frequenza settimanale). Con il
  refresh unico ogni card fa una query per giro invece di tre.
- **Roboto** non bundlato: arriva da `fonts.gstatic.com` in parallelo al Firebase SDK;
  basta il `preconnect`.
- **`--pwa-strategy=none`** non applicabile: il flag non esiste più in Flutter 3.41.6.
- **Cache asset**: il default Hostinger è già 7 giorni; `.htaccess` aggiunge solo i file
  senza hash che devono restare freschi (`main.dart.wasm`/`.mjs`, `AssetManifest*`,
  `FontManifest.json`) e `AddType application/wasm`. Superato dalla Fase 4: con la build
  dart2js questi file passano a `no-cache` (vedi sotto). Da verificare dopo il deploy:
  `curl -I https://app.fithousemonza.it/main.dart.js` → `Cache-Control: no-cache` e un
  `ETag`, così i reload successivi rispondono 304.

## Fase 4 — codice admin differito, build dart2js (26/09/2026)

Dal 26/09/2026 la produzione e CI buildano con `flutter build web --release` (dart2js),
non più `--wasm`: con `--wasm` i `deferred as` finiscono tutti in `main.dart.wasm`.

Codice spostato in librerie deferred: `AdminHomeSections` (sezioni admin della Home),
`AdminUsersPage`, `AdminDashboardPage`, `UserListDrawer`. Misure gzip -9 della build dart2js,
prima (commit 5c49c87, solo `Protected` differito) e dopo:

| | Prima | Dopo |
|---|---:|---:|
| `main.dart.js` | 917.729 | 919.153 |
| part caricati da un socio (`protected`) | 198.198 (3 part) | 170.516 (23 part) |
| part in più per un admin | — | 47.919 (10 part) |

Un socio scarica ~28 KB gzip in meno (−14% sul chunk dell'area protetta); un admin ~20 KB in
più in totale (lo split costa qualche ottimizzazione trasversale) e più richieste. I part sono
piccoli e tanti: con `no-cache` ogni reload li rivalida (304), in parallelo su HTTP/2.

**Costo dello spegnimento di wasm, per browser.** Il loader di Flutter 3.41 usa wasm **solo su
Chromium** (`wasmAllowList` di default: blink sì, webkit/gecko no): Safari/iOS e Firefox
ricevevano `main.dart.js` + CanvasKit anche con la build `--wasm`, quindi per loro cambia solo
il guadagno qui sopra. Su Chromium (Android, Chrome/Edge desktop), primo accesso di un socio:

| | `--wasm` | dart2js |
|---|---:|---:|
| app | 1.272 KB (`main.dart.wasm` + `.mjs`, tutto incluso) | 1.090 KB (`main.dart.js` + part di `protected`) |
| renderer da gstatic | 1.513 KB (`skwasm.wasm`) | 2.153 KB (`canvaskit.wasm`, variante chromium) |
| totale | ~2,79 MB | ~3,24 MB |

Il renderer arriva da `www.gstatic.com` con cache lunga, quindi lo si paga soprattutto al
primo accesso; dart2js è anche più lento a runtime del codice wasm. Il primo frame misurato in
locale (desktop, cache calda) è nel rumore: ~1,3–2,2 s per entrambe. Alternativa se il costo
su Chromium pesa: tornare a `--wasm`, che produce comunque anche `main.dart.js` con questi part
per i browser non Chromium (lo split resterebbe utile solo lì). In quel caso
`tool/check_deferred_split.py` va adattato: oggi fallisce apposta se trova `main.dart.wasm`.

Verifica: `tool/check_deferred_split.py build/web` (in `ci.yml` e `staging.yml`) e QA
sull'emulatore con admin (Home, Utenti, Dashboard, drawer, simulazione di un socio e uscita):
ogni libreria carica solo i suoi part, e al resume dopo la simulazione non restano letture del
socio.

## Localizzazioni solo italiane e scelta del motore (26/09/2026)

Composizione di `main.dart.js` (da source map, build dart2js): il grosso è framework Flutter e
SDK Dart; le due voci evitabili erano `flutter_localizations` (~309 KB raw: testi
Material/Cupertino e date di ~80 lingue) e, nel motore, le tabelle dei font di fallback
(~250 KB raw, interne all'engine e non configurabili).

`lib/utils/italian_localizations.dart` sostituisce i delegate `Global*Localizations` con
delegate che costruiscono direttamente le classi italiane:

| `main.dart.js` | Prima | Dopo |
|---|---:|---:|
| raw | 3.304.432 | 2.765.430 |
| gzip -9 | 919.198 | 810.631 |
| brotli (come lo serve Hostinger) | 707.816 | 631.574 |

Motore grafico, scaricato da gstatic in brotli con cache di un anno (condivisa tra i siti Flutter
con la stessa revisione dell'engine):

| Motore | Chi lo riceve | brotli |
|---|---|---:|
| CanvasKit "chromium" | Chrome, Edge, Android | 1,63 MB |
| CanvasKit completo | Safari/iOS, Firefox | 2,25 MB |
| skwasm | Chromium, solo con build `--wasm` | 1,21 MB |
| skwasm_heavy | Safari/Firefox, solo forzando wasm | 1,83 MB |

**Decisione: restare su dart2js.** La produzione (deploy del 14/07/2026) non ha mai servito
`main.dart.wasm`: gira già dart2js, quindi lo spegnimento di `--wasm` non cambia nulla per gli
utenti reali. Con dart2js non esiste una variante di CanvasKit più piccola da scegliere (il
loader prende già "chromium" dove può). Si torna a valutare `--wasm` quando
`--enable-wasm-deferred-loading` (beta 3.48, assente nella stable 3.47.5) arriverà in stable:
allora wasm e split deferred saranno compatibili. Wasm su Safari/iOS non è attivo di default in
nessun canale (stable 3.47.5, beta 3.49, master); si può forzare con `wasmAllowList` ma sotto
Safari 26.2 rischia crash, e il team Flutter non lo supporta ancora
([#178893](https://github.com/flutter/flutter/issues/178893)).
