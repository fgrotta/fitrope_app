# Report di esecuzione test e verifica upgrade Flutter

**Data:** 21 agosto 2026<br>
**Workspace:** `fitrope_app/bandung`<br>
**Target applicativo usato:** Firebase Emulator Suite, progetto
`fit-rope-app-1f575`<br>
**SDK corrente del progetto/CI:** Flutter 3.41.6, Dart 3.11.4, DWDS 26.2.3<br>
**SDK valutato senza installazione globale:** Flutter 3.47.1, Dart 3.13.1,
DWDS 27.1.2

## Esito sintetico

- Le suite deterministiche sono verdi: **365 test Flutter**, **273 test Jest
  delle Functions** e **33 test di integrazione Functions/Firestore Rules**.
- Tre scenari E2E web hanno completato con esito positivo contro gli emulatori:
  login/sessione, autorizzazione per ruolo e iscrizione/disiscrizione.
- Il flusso waitlist ha esercitato realmente `subscribeToCourse` e
  `joinWaitlist`, ma la sua validazione finale non è ancora certificata: dopo
  una correzione all'attesa della UI, i rerun sono stati bloccati prima
  dell'avvio dell'app dalla connessione Flutter Web/DWDS.
- Gli E2E di gestione corsi e registrazione bifase non sono stati eseguiti.
- Flutter 3.47.1 è compatibile con le suite unit/widget del repository e porta
  correzioni DWDS pertinenti. Tuttavia, in **due tentativi E2E su due** non ha
  stabilito la connessione di debug: l'upgrade è raccomandabile in una PR
  dedicata, ma **non è una soluzione dimostrata** al blocco E2E osservato.
- Nessun test ha usato Firebase produzione. Il bootstrap E2E ha mostrato
  esplicitamente il marker `EMULATORE FIREBASE ATTIVO`.

## Cosa sono i blocchi DWDS

DWDS significa **Dart Web Debug Service**. Non è un lock applicativo o un
blocco di Firestore: è il ponte di debug che permette agli strumenti Flutter
di controllare una app Dart compilata per il browser.

Nel percorso E2E web sono coinvolti più componenti:

```text
flutter drive
    ├── avvia/controlla Chrome tramite ChromeDriver
    ├── compila e serve l'app Flutter Web in debug
    └── DWDS usa il Chrome DevTools Protocol
            └── espone un servizio simile al Dart VM Service
                    └── integration_test e il driver si collegano all'app
```

Il messaggio:

```text
Instance of 'AppConnectionException'
```

indica che questo handshake non è stato completato. Di solito Chrome è stato
avviato, ma Flutter/DWDS non ha trovato in tempo il contesto Dart corretto o ha
perso la sessione DevTools/WebSocket. In questo caso:

- il codice del test non è ancora partito;
- le callable Firebase non sono state esercitate;
- l'esito non va classificato come fallimento funzionale dell'app;
- non va neppure considerato un successo solo perché il processo wrapper
  restituisce accidentalmente exit code `0`.

Per questo il runner locale è stato reso *fail-closed*: accetta l'esecuzione
solo se nel log compare il marker finale `All tests passed.`, riconosce
separatamente `AppConnectionException` e limita i retry ai soli errori
infrastrutturali.

Il problema non è specifico di FitRope. È presente un issue Flutter ancora
aperto relativo a `AppConnectionException` non deterministiche in debug web;
nel caso riportato anche upstream le modalità profile/release funzionano più
spesso del debug. Vedere [Flutter issue #181357](https://github.com/flutter/flutter/issues/181357).

## Ambiente verificato

| Componente | Versione/esito |
|---|---|
| macOS | host locale, timezone Europe/Rome |
| Flutter corrente | 3.41.6 stable, revision `db50e20168` |
| Dart corrente | 3.11.4 |
| DevTools corrente | 2.54.2 |
| DWDS corrente | 26.2.3, pin di `flutter_tools` |
| Flutter in prova isolata | 3.47.1, revision `6655482ec0` |
| Dart in prova isolata | 3.13.1 |
| DevTools in prova isolata | 2.60.0 |
| DWDS in prova isolata | 27.1.2 |
| Chrome | 151.0.7922.170 |
| ChromeDriver | 151.0.7922.138, porta 4444 |
| Java | 21+ per Emulator Suite |
| Firebase target | Emulator Suite, `fit-rope-app-1f575` |

Chrome e ChromeDriver condividono `MAJOR.MINOR.BUILD` (`151.0.7922`), quindi
rispettano la regola di compatibilità indicata dalla documentazione ufficiale
[ChromeDriver version selection](https://developer.chrome.com/docs/chromedriver/downloads/version-selection).
La diversa patch `.170`/`.138` non è, da sola, evidenza di incompatibilità.

I workflow `ci.yml`, `staging.yml` e `release.yml` sono tutti fissati a Flutter
3.41.6; l'esperimento non ha modificato questi pin né l'installazione Flutter
globale.

## Criterio usato per classificare gli esiti

| Stato | Significato |
|---|---|
| **PASS** | Il test è partito e ha prodotto il marker finale `All tests passed.` |
| **FAIL applicativo** | Il test è partito e un'asserzione o il codice applicativo ha fallito con dettaglio utilizzabile |
| **BLOCCATO infrastruttura** | Chrome/DWDS non ha collegato il driver all'app; il corpo del test non è partito |
| **PARZIALE** | Una parte del flusso è stata osservata, ma manca un rerun verde dell'intero scenario |
| **NON ESEGUITO** | Non esiste un risultato da interpretare |

Questa distinzione evita sia falsi negativi sull'app sia falsi verdi del runner.

## Suite deterministiche eseguite

### Flutter unit e widget

Comando:

```bash
flutter test
```

Esito: **365/365 test passati** con Flutter 3.41.6.

La suite include logica di dominio, serializzazione, calendari e timezone,
abbonamenti, widget responsive, gestione utenti, dashboard, corsi ricorrenti e
regressioni del loader corsi aggiunte durante l'implementazione del piano.

### Analisi statica Flutter

Comando:

```bash
flutter analyze --no-fatal-infos
```

Esito: **nessun problema rilevato** con Flutter 3.41.6.

### Cloud Functions — unit test Jest

Comando:

```bash
cd functions && npm test
```

Esito: **13 suite, 273/273 test passati**, durata Jest 4,596 secondi.

Sono inclusi handler, eligibility, rimborsi, autorizzazioni amministrative,
waitlist, notifiche, assegnazione abbonamenti e convenzioni del backend.

### Cloud Functions e Firestore Rules — integrazione emulatori

Comando:

```bash
cd functions && npm run test:integration
```

Esito: **2 suite, 33/33 test passati**, durata Jest 23,446 secondi.

Questa suite ha avviato callable e rules reali nell'Emulator Suite e copre
transazioni, concorrenza e autorizzazioni. Gli emulatori sono stati spenti con
cleanup regolare al termine.

## E2E Flutter Web eseguiti

Tutti i risultati validi di questa sezione sono locali e puntano agli
emulatori. Non sono risultati staging.

| Scenario | Stato | Evidenza principale |
|---|---|---|
| `login_test.dart` | **PASS** | Connessione debug in 43,3 s; corpo test 41 s; marker finale presente |
| `role_navigation_test.dart` | **PASS** | Connessione debug in 62,3 s; corpo test 22 s; marker finale presente |
| `subscribe_to_course_test.dart` | **PASS** | Connessione debug in 47,7 s; iscrizione, disiscrizione e cleanup completati; marker finale presente |
| `waitlist_swap_test.dart` | **PARZIALE / rerun bloccato** | Subscribe e join waitlist osservati; asserzione UI finale corretta, ma i successivi rerun debug non hanno collegato DWDS |
| `course_management_test.dart` | **NON ESEGUITO** | Bloccato dalla stabilità del runner prima di ampliare la matrice |
| `registration_unverified_test.dart` | **NON ESEGUITO** | Non avviata l'orchestrazione bifase |
| `registration_verified_login_test.dart` | **NON ESEGUITO** | Dipende dalla prima fase e dalla verifica Admin SDK |

### Login, logout e sessione — A2

Sono stati verificati:

1. login valido e accesso all'area protetta;
2. credenziali errate con permanenza fuori dall'area protetta;
3. persistenza della sessione dopo il restart e logout verso la welcome;
4. account disattivato escluso dall'area protetta.

Il reporter mostra `+6` perché include `setUpAll` e `tearDownAll`; i casi di
business sono quattro.

Il log ha anche evidenziato letture Firestore ancora pendenti durante alcuni
cambi di sessione, terminate con `permission-denied` dopo il sign-out. Il test
è passato, ma il segnale non è stato ignorato: il teardown è stato modificato
per smontare l'albero protetto prima del logout e le letture asincrone delle
pagine sono ora gestite. La suite completa deve essere rieseguita quando DWDS
torna stabile per certificare la correzione senza warning.

### Autorizzazioni e navigazione per ruolo — A3

Un test composito ha verificato, in sequenza:

- utente base;
- trainer;
- amministratore;
- visibilità delle destinazioni per ruolo;
- protezione dell'accesso diretto alla route gestionale.

Il test è terminato con marker verde.

### Iscrizione e disiscrizione — A8/A9

Il test ha creato un corso dinamico namespaced, effettuato l'iscrizione come
utente, esercitato `subscribeToCourse` e `unsubscribeFromCourse`, quindi si è
ri-autenticato come Admin per il cleanup tramite `deleteCourse`.

Questo conferma il cablaggio UI → callable → Firestore → UI per un percorso
rappresentativo. Non sostituisce la matrice completa di eligibility e rimborso,
che è coperta dalle suite Dart/Jest e di integrazione emulatori.

### Waitlist e swap — A10

Nel run funzionale sono stati osservati:

- iscrizione del primo utente al corso da un posto;
- `joinWaitlist` del secondo utente;
- transizione fino alla vista amministrativa.

L'asserzione cercava immediatamente il nome dell'iscritto dopo l'espansione
della card. Il dato viene caricato in modo asincrono, quindi il test è stato
corretto usando un'attesa esplicita sia per i nomi sia per il conteggio
waitlist. I rerun successivi non hanno raggiunto questa asserzione a causa del
blocco DWDS; lo scenario resta pertanto **parziale**, non verde.

Un tentativo in profile ha compilato in 59,3 secondi ma ha restituito un
fallimento privo di stack utile. Profile/release non sono stati accettati come
sostituti del debug perché riducono la capacità diagnostica del driver.

## Problemi scoperti durante l'esecuzione

### 1. Runner che poteva produrre falsi verdi

In alcune combinazioni `flutter drive`/wrapper il processo terminava senza un
risultato di test affidabile. Il criterio ora è il marker nel log, non soltanto
l'exit code.

### 2. Timer dello splash nel clock del widget test

Una `Future.delayed` reale di tre secondi non avanzava con le normali attese
del test. L'helper usa ora `tester.pump(const Duration(seconds: 3))`, così il
clock controllato dal binding fa progredire lo splash in modo deterministico.

### 3. Letture pendenti tra due utenti

Il logout poteva invalidare l'autenticazione mentre Home/Calendario avevano
ancora query Firestore attive. Il cambio utente ora smonta prima la UI protetta
e aspetta la chiusura delle attività prima del sign-out.

### 4. Contenuto amministrativo asincrono

La card corso viene renderizzata prima che nomi e dettagli degli iscritti siano
disponibili. Un `pumpAndSettle` generico non esprime questa condizione; il test
attende ora il finder specifico con un timeout esplicito.

### 5. ChromeDriver non è la causa dimostrata

Il driver risponde sulla porta 4444 e la sua versione è compatibile con Chrome
secondo la regola ufficiale. I run verdi confermano inoltre che la stessa
coppia Chrome/ChromeDriver può funzionare. Il guasto è intermittente nel
livello di connessione debug, non un mismatch sistematico del browser.

## Verifica dell'upgrade Flutter

### Versione scelta

La stable ufficiale più recente verificata è Flutter 3.47.1, pubblicata il 19
agosto 2026. Il controllo è stato eseguito con un SDK isolato in `.context`,
senza cambiare `/usr/local/share/flutter` e senza aggiornare i workflow. Le
release ufficiali sono elencate nelle [Flutter release notes](https://docs.flutter.dev/release/release-notes),
con i dettagli della serie nelle [release notes di Flutter 3.47](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0).

### Compatibilità delle dipendenze

Con `flutter pub get --enforce-lockfile`, Flutter 3.47.1 rifiuta correttamente
il lock corrente perché il nuovo SDK richiede cinque versioni pinned diverse:

| Pacchetto | Flutter 3.41.6 | Flutter 3.47.1 |
|---|---:|---:|
| `intl` | 0.20.2 | 0.20.3 |
| `matcher` | 0.12.19 | 0.12.20 |
| `meta` | 1.17.0 | 1.19.0 |
| `test_api` | 0.7.10 | 0.7.12 |
| `vector_math` | 2.2.0 | 2.4.2 |

Un normale `flutter pub get` nella copia isolata ha aggiornato soltanto queste
cinque risoluzioni. Il lockfile reale del workspace non è stato modificato.

### Risultati con Flutter 3.47.1

| Prova | Esito |
|---|---|
| `flutter pub get` nella copia | **PASS**, con i cinque aggiornamenti sopra |
| `flutter test` | **PASS**, 365/365 |
| `flutter analyze --no-fatal-infos` | **PASS**, nessun problema |
| E2E login debug, tentativo 1 | **BLOCCATO**, attesa iniziale 35,8 s e nessuna sessione ChromeDriver/DWDS dopo oltre 3 minuti |
| E2E login debug, tentativo 2 | **BLOCCATO**, attesa iniziale 42,2 s e nessuna sessione ChromeDriver/DWDS dopo oltre 1 minuto |

Nei due tentativi il corpo del test non è partito e i processi sono stati
interrotti manualmente. Non è comparsa una nuova incompatibilità Dart o una
failure applicativa; il sintomo è rimasto nel collegamento web debug.

### Perché l'upgrade resta comunque interessante

Il passaggio porta DWDS da 26.2.3 a 27.1.2. Nel
[changelog ufficiale DWDS](https://github.com/dart-lang/webdev/blob/main/dwds/CHANGELOG.md)
le versioni intermedie includono interventi direttamente pertinenti:

- DWDS 26.2.5 aggiunge retry alle connessioni Chrome Proxy Service;
- DWDS 27.0.1 corregge hang di riconnessione WebSocket e disconnessioni fuori
  ordine;
- DWDS 27.1.1 corregge errori di deserializzazione e gestione del ping client.

Anche Flutter 3.44 contiene una correzione per il caso occasionale in cui gli
strumenti non trovano il tab Chrome ([PR Flutter #183737](https://github.com/flutter/flutter/pull/183737)).
Questi interventi rendono l'upgrade sensato, ma l'issue più vicina al sintomo
osservato resta aperta e la prova locale 0/2 non consente di promettere un E2E
stabile.

## Raccomandazione

### Decisione

**Aggiornare a Flutter 3.47.1 in una PR dedicata**, perché:

- le 365 prove Flutter e l'analisi statica sono già compatibili;
- l'upgrade include più generazioni di correzioni DWDS;
- mantenere Flutter 3.41.6 significa restare su DWDS 26.2.3, prima dei retry
  Chrome Proxy aggiunti in 26.2.5.

L'upgrade non deve però essere presentato come fix definitivo di
`AppConnectionException`.

### Piano di adozione proposto

1. Aggiornare `pubspec.lock` con le cinque risoluzioni SDK-pinned elencate.
2. Portare **tutti** i pin dei workflow `ci.yml`, `staging.yml` e `release.yml`
   alla stessa versione Flutter.
3. Accettare e revisionare separatamente l'aggiornamento automatico delle
   esclusioni in `analysis_options.yaml`, invece di lasciarlo come effetto
   collaterale non discusso.
4. Rieseguire test Flutter, analyze, build web WASM, Functions e integrazione
   emulatori.
5. Eseguire un confronto controllato di almeno dieci cold start E2E per SDK,
   sulla stessa coppia Chrome/ChromeDriver, registrando:
   - tempo fino a `Debug service listening`;
   - numero di `AppConnectionException`;
   - numero di timeout senza sessione;
   - durata del corpo del test;
   - marker finale.
6. Conservare un timeout per singolo tentativo e un numero limitato di retry
   solo per errori DWDS riconosciuti. Un'asserzione applicativa non deve mai
   essere ritentata automaticamente.
7. Allegare i log del browser, di `flutter drive` e degli emulatori come
   artifact CI quando il collegamento fallisce.

Per la CI è preferibile installare una coppia **Chrome for Testing +
ChromeDriver** della stessa release, invece di lasciare che Homebrew aggiorni i
due componenti in momenti diversi. In locale Homebrew resta adeguato, purché si
verifichi `MAJOR.MINOR.BUILD` prima del run.

## Test non eseguiti e lavoro residuo

- E2E completo waitlist/swap dopo la correzione dell'attesa UI.
- E2E creazione corso singolo e ricorrente.
- Registrazione bifase: non verificato → Admin SDK verify → login verificato →
  cleanup `if: always()`.
- E2E contro staging dopo `deploy-rules`.
- Smoke Playwright sull'artefatto GitHub Pages.
- `flutter build web --wasm --release` con Flutter 3.47.1.
- Gate di formattazione completo `dart format --set-exit-if-changed .` dopo
  l'eventuale upgrade.

Finché il runner debug non produce connessioni ripetibili, i test ancora non
certificati non devono essere usati come gate obbligatorio della PR. Le suite
deterministiche e gli E2E già verdi restano evidenza valida, mentre waitlist,
gestione corsi e registrazione devono essere indicati esplicitamente come
parziali o non eseguiti.

## Comandi di riferimento

```bash
# Flutter corrente
flutter test
flutter analyze --no-fatal-infos

# Functions
cd functions && npm test
cd functions && npm run test:integration

# E2E web: un target per invocazione, chromedriver già sulla porta 4444
flutter drive \
  --debug \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/login_test.dart \
  -d chrome \
  --browser-dimension=1200x900 \
  --dart-define=USE_EMULATOR=true \
  --dart-define=TEST_RUN_NAMESPACE=manuale \
  --dart-define-from-file=integration_test/test_env.emulator.json
```

Il comando E2E deve essere eseguito mentre Auth, Firestore e Functions Emulator
sono attivi e dopo il seed. `flutter test -d chrome` non supporta gli
integration test web di questa suite; il comando corretto è `flutter drive`.
