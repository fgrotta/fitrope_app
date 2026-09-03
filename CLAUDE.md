# CLAUDE.md

Per architettura, modelli dati e regole di business dettagliate vedi `AGENTS.md`.

## Comandi

### Flutter

```bash
flutter pub get          # installa dipendenze
flutter test             # esegui tutti i test
flutter analyze          # analisi statica
flutter format --set-exit-if-changed .  # check formattazione
flutter build web --debug               # build web
flutter run -d chrome                   # avvio locale
```

### Cloud Functions (functions/)

```bash
cd functions
npm install              # installa dipendenze Node
npm run build            # compila TypeScript
npm test                 # Jest sull'handler OneSignal
```

### Deploy e gestione secret

```bash
# Deploy (il predeploy compila automaticamente via tsc)
firebase deploy --only functions

# Aggiornare il secret OneSignal REST API Key
firebase functions:secrets:set ONESIGNAL_REST_API_KEY
firebase deploy --only functions   # re-deploy per bindare il nuovo valore

# Vedere i log runtime
firebase functions:log --only sendOneSignalNotification

# Eliminare la function
firebase functions:delete sendOneSignalNotification
```

Dopo ogni modifica, esegui almeno `flutter test` e `flutter analyze`. Se tocchi `functions/`, esegui anche `npm test` nella cartella `functions/`.

## Verifica live e lezioni operative

> **Policy — salva cosa impari.** Al termine di ogni sviluppo significativo, registra le lezioni apprese (trappole dell'ambiente, errori da non ripetere, pattern utili): se hanno valore generale per il progetto aggiungile a questa sezione; in ogni caso annotale nella memoria di progetto. Così le scoperte non vanno riscoperte alla sessione successiva.

Lezioni dal lavoro di sviluppo UI (verifica delle modifiche nel browser):

- `flutter run -d web-server` **ricompila solo all'avvio o su hot-restart** (`R` da stdin). Un'istanza lanciata in background non riceve `R`: dopo ogni modifica al codice **riavvia il run** (kill della porta + relaunch), non basta ricaricare la pagina.
- Il browser serve un `main.dart.js` cache-ato: dopo il relaunch fai un **hard reload** (Cmd/Ctrl+Shift+R), altrimenti vedi il build vecchio (sintomo tipico: il default sembra sbagliato o "la modifica non ha effetto").
- Per testare i **breakpoint responsive** verifica la larghezza reale (`window.innerWidth`): il ridimensionamento della finestra può essere inaffidabile. Breakpoint in `lib/layout/breakpoints.dart` (mobile <600, tablet <900, desktop <1600, largeDesktop ≥1600).
- **Pre-commit hook**: in alcuni ambienti `flutter` riporta SDK `0.0.0-unknown` e l'hook fallisce anche con test/analyze verdi → committa con `--no-verify` **dopo** aver eseguito a mano `flutter analyze` + `flutter test`.

### Deploy web / aggiornamento PWA (cache stantia su iOS)

- Produzione: `https://app.fithousemonza.it`, hosting Hostinger/LiteSpeed, deploy **manuale** (`flutter build web` → upload di `build/web`). `web/.htaccess` viene copiato automaticamente in `build/web/` dal build Flutter: è il modo per far applicare regole di cache a Hostinger senza toccare il pannello.
- **`main.dart.js`, `flutter_service_worker.js`, `flutter_bootstrap.js`, `flutter.js` non hanno mai un hash nel nome**: restano identici da un build all'altro (il versioning è gestito internamente dal service worker generato da Flutter via confronto hash-per-file, non dal filename). Qualsiasi cache lunga su questi file (anche solo un default del server per estensione `.js`, come i 7 giorni di default riscontrati su Hostinger/LiteSpeed) blocca i client su una versione vecchia finché la cache non scade — `web/.htaccess` la limita a 30 minuti per i file "vivi" (index.html, version.json, manifest.json + i file sopra).
- Un tentativo precedente di forzare l'update via JS (unregister di tutti i service worker + wipe di tutta la Cache Storage + reload cache-busted) è stato revertito perché causava un **reload loop infinito**: il reload rileggeva comunque `main.dart.js`/`flutter_service_worker.js` dalla cache HTTP del browser (non toccata dal wipe della Cache Storage, che è uno strato diverso), quindi il mismatch di versione si ripresentava a ogni giro. Prima di reintrodurre logica di forzatura via JS, verificare sempre che gli header di cache lato server siano già corretti — altrimenti nessuna logica JS può risolvere il problema.

### UI responsive / layout shift

- Liste di card (es. `CalendarPage`): su desktop usa griglie multi-colonna con `LayoutBuilder` (n. colonne = larghezza disponibile / larghezza-min-card) e disposizione "masonry" per gestire le altezze variabili; evita la singola colonna stretta che spreca lo spazio orizzontale.
- Per un default che dipende dal layout (es. vista mese su desktop, settimana su mobile) usa uno stato **nullable** (`bool?`) risolto a runtime con `valore ?? isDesktop(context)`: così il default segue il breakpoint ma il toggle manuale dell'utente mantiene la precedenza.
- Evita stringhe **transitorie di caricamento** dentro una `description` condivisa renderizzata riga-per-riga (`CourseCard._buildMetadata`): appaiono e poi spariscono al termine della fetch → **salto di altezza** della card a ogni rebuild. I dati finali vanno in widget stabili (pill di conteggio, dialog, box dedicato), non nei metadati testuali.

## Convenzioni

- UI in italiano. Non tradurre stringhe UI in inglese salvo richiesta esplicita.
- Localizzazione date: `it_IT` via `intl`. Usa `formatDate` da `lib/utils/formatDate.dart`.
- Serializzazione manuale: se aggiungi/modifichi campi nei modelli, aggiorna sempre sia `toJson` sia `fromJson` in `lib/types/`.
- Nomi file Dart: rispetta il case esatto (es. `HomePage.dart`, non `homepage.dart`).
- Stato globale Redux minimale: non aggiungere campi a `AppState` senza necessita reale.
- Dopo mutazioni su corsi/utenti, invalida la cache (`refresh_manager`, `user_cache_manager`).
- Usa transazioni Firestore per operazioni che toccano contemporaneamente utente e corso.
- **Pull request**: apri sempre le PR nel fork `fgrotta/fitrope_app` con base `main`, mai verso l'upstream `dellarosamarco/fitrope_app`. Questo repo è un fork, quindi `gh pr create` di default punterebbe al parent: usa `gh pr create --repo fgrotta/fitrope_app --base main`.

## Aree sensibili

La logica di iscrizione/disiscrizione ai corsi e la parte piu critica. Se la modifichi:

1. Leggi `lib/api/courses/README_ISCRIZIONI.md`
2. Esegui i test: `flutter test`
3. File chiave: `lib/api/courses/subscribeToCourse.dart`, `unsubscribeToCourse.dart`, `lib/utils/course_unsubscribe_helper.dart`

## Notifiche e integrazioni

### OneSignal (email + push)

- REST API key **non** nel codice Flutter: sta in Google Secret Manager, usata solo dalla Cloud Function.
- Se modifichi il payload inviato a OneSignal, non includere `app_id` — lo inietta la function server-side.
- `notification_service.dart` chiama `FirebaseFunctions.instance.httpsCallable('sendOneSignalNotification')`.
- Su web le chiamate dirette a OneSignal falliscono per CORS: passa sempre dalla Cloud Function.
- **Push web disabilitate**: il Web SDK OneSignal è commentato in `web/index.html` e `onesignal_web.dart` è no-op. Le email su web passano via Cloud Function `sendOneSignalNotification`, che garantisce da sola i destinatari su OneSignal (vedi punto "Alias OneSignal" sotto); `ensureOneSignalUser` resta chiamata al login. Le push native restano attive su Android/iOS via `onesignal_flutter`.
- Ogni corso ha i flag `reminderEnabled` e `waitlistEnabled`: se false, `scheduleTrialReminder` / `notifyWaitlistUsers` saltano l'invio e `getCourseState` ritorna `FULL` invece di `CAN_WAITLIST`.
- **Alias OneSignal prima dell'invio**: `include_aliases: {external_id: [...]}` fallisce silenziosamente (200 OK, `recipients: 0`, nessun errore) se l'utente non ha mai fatto login — l'alias viene creato solo al login self-service (caso tipico: utente creato da Admin/walk-in e mai loggato). La garanzia è **server-side** in `sendOneSignalNotificationHandler` (`functions/src/handler.ts`): per ogni invio con `target_channel: 'email'` + `include_aliases.external_id`, la function legge l'email da Firestore (`users/{uid}`) e chiama `ensureOneSignalEmailSubscription` (idempotente) prima della POST. I call-site client NON devono più fare l'ensure prima degli invii; resta solo al login. `postToOneSignal` logga warning su 200-con-errors e `recipients: 0` (visibili con `firebase functions:log --only sendOneSignalNotification`). Nota: l'ensure riabilita anche una subscription email disattivata dal link di unsubscribe OneSignal — il filtro reale sono i flag `emailNotificationsEnabled`/`pushNotificationsEnabled` su Firestore. Gli invii server-side diretti via `postToOneSignal` (es. cron certificati) devono invece chiamare l'ensure esplicitamente, come fa `runCertificateEmails`.
- **Logout**: la rimozione dell'email da OneSignal al logout è temporaneamente disabilitata (codice commentato in `lib/authentication/logout.dart`).
- **Debug email**: in `kDebugMode` è disponibile un FAB in `Protected` che apre `DebugEmailPage` (`/debug-email`). Permette di inviare email di test (waitlist e promemoria prova) all'utente corrente senza triggering reale degli eventi. Le funzioni `sendTestWaitlistEmail` / `sendTestTrialReminderEmail` sono in `notification_service.dart`.

### WhatsApp lezioni demo via webhook Make

- Il messaggio WhatsApp **non** lo manda l'app: un `POST` verso un Custom webhook Make fa partire un template approvato da Meta. Il testo si modifica nello scenario Make, senza deploy.
- Due eventi, un solo webhook, distinti dal campo `tipo` del body:
  - `conferma` — callable `notifyDemoLessonBooked`, chiamata all'iscrizione da `subscribeToCourse.dart` (entrambi i rami, self-service e admin/trainer);
  - `promemoria` — cron `sendDemoLessonWhatsappReminders`, `0 19 * * *` Europe/Rome, per le lezioni del giorno dopo.
- **Il body è un contratto con lo scenario Make**: `{tipo, nome, numero_di_telefono, corso, giorno, orario}`, tutti stringhe non vuote. Make impara lo schema dal primo payload: aggiungere o rinominare una chiave richiede un "Redetermine data structure" sul webhook, altrimenti il campo non è selezionabile nei moduli a valle. I parametri dei template WhatsApp non ammettono valori vuoti, newline, tab o 4+ spazi — `sanitizeTemplateParam` in `functions/src/makeWebhook.ts` se ne occupa.
- **La chiave di autenticazione va nell'header `Demo-Reminder`, non nel body**: così non finisce nella struttura dati appresa dal webhook né nella cronologia delle esecuzioni. Nello scenario serve "Get request headers" attivo.
- Secret in Google Secret Manager (l'URL del webhook **è** una credenziale: chi lo conosce può iniettare messaggi a nostro nome):

```bash
firebase functions:secrets:set MAKE_WEBHOOK_URL
firebase functions:secrets:set MAKE_WEBHOOK_KEY
firebase deploy --only functions   # re-deploy per bindare i nuovi valori
firebase functions:log --only sendDemoLessonWhatsappReminders
```

- **Il gate lato client non include `kDebugMode`** (`lib/utils/is_demo_lesson_user.dart`): a differenza di email e push — che in debug partono per qualunque utente — ogni WhatsApp è reale e a pagamento. Non reintrodurre `kDebugMode ||` in quel controllo: c'è `test/is_demo_lesson_user_test.dart` a fare da guardia.
- **Idempotenza**: ogni invio è registrato in `demoLessonWebhookLog/{kind}_{userId}_{courseId}` (solo identificativi, nessun telefono né email — le security rules non sono versionate in questo repo). Il claim è creato con `create()` *prima* della POST e rilasciato con `delete()` se questa fallisce, così un run successivo può ritentare. Chi si iscrive il giorno prima della lezione riceverebbe due messaggi a poche ore di distanza: il cron controlla `booked_*` con `sentAt` nello stesso giorno di Roma e salta (`already_notified_today`).
- `postToMake` **non lancia mai** e non deserializza la risposta (Make risponde `Accepted` in testo, non JSON). Ha un `AbortSignal.timeout` obbligatorio: undici non ha un timeout breve di default e uno scenario appeso bloccherebbe cron e callable per minuti. URL e chiave sono esclusi da ogni log (viene loggato solo l'host).
- **Gli errori a valle del webhook non tornano indietro**: numero non su WhatsApp, template non approvato, credito esaurito danno comunque `200 Accepted`. Configura le notifiche di errore dello scenario in Make, altrimenti i fallimenti sono invisibili.
- Debug: in `kDebugMode` la `DebugEmailPage` ha una sezione WhatsApp con due bottoni (`conferma` / `promemoria`) che mandano il payload **al numero digitato** via `sendTestDemoLessonWebhook`, senza toccare Firestore né il log degli invii. I campi *Nome e cognome*, *Giorno*, *Nome corso* e *Orario* finiscono verbatim nel body (i vuoti ricadono su un default lato function) e il body effettivamente inviato viene mostrato sotto i bottoni, così si verifica il messaggio prima di mandarlo a un utente reale. Attenzione: *Giorno* ha un campo suo perché il formato WhatsApp (`28 aprile 2026`) differisce da quello delle email (`Lunedì 28 Aprile 2025`). Il pulsante di lookup per email precompila nome, cognome e `numeroTelefono` dal documento utente.
- `romeDayWindow` (`functions/src/romeTime.ts`) ha un'asimmetria DST **nota e voluta**: usa l'offset della mezzanotte del giorno target anche per l'estremo superiore, quindi nel giorno del fall-back perde l'ultima ora e in quello dello spring-forward sfora di un'ora. Per i certificati (salvati a 23:59) è innocuo e correggerlo cambierebbe quel comportamento; il cron WhatsApp usa quindi `romeDayWindowPadded` + filtro `isSameRomeDay`.

## Struttura rapida

- Entry point: `lib/main.dart`
- Route: `lib/router.dart` (7 route statiche + 1 debug-only)
- Stato: `lib/state/` (Redux con thunk)
- Pagine: `lib/pages/welcome/` (auth) e `lib/pages/protected/` (area protetta)
- API Firestore: `lib/api/` (authentication + courses)
- Modelli: `lib/types/fitropeUser.dart`, `lib/types/course.dart`
- Layout responsive: `lib/layout/` (breakpoints + AppShell)
- Servizi esterni: `lib/services/` (OneSignal mobile + web, notifiche, email templates)
- Cloud Functions: `functions/src/` (TypeScript: proxy OneSignal, cron certificati, webhook Make)

## TODO / Da aggiornare

Punti aperti da affrontare in un secondo momento (non ancora fatti):

- **Promemoria OneSignal ancora programmato client-side**: `scheduleTrialReminder` (`lib/services/notification_service.dart`) viene invocato all'iscrizione e schedula email e push su OneSignal con `send_after` alle 19:00 della sera prima. La notifica in coda **non è annullabile** — se l'utente si disiscrive, se il corso viene cancellato o spostato, o se `reminderEnabled` viene disattivato dopo, il messaggio parte comunque (e non salviamo il notification id per poterlo cancellare). Ora che `sendDemoLessonWhatsappReminders` fa già la stessa selezione di destinatari la sera prima, si può spostare anche email e push su quel cron, inviandole subito via `postToOneSignal` senza `send_after` (come fa `runCertificateEmails`) e rimuovere la chiamata dal client. Costo da mettere in conto: i template email vivono in Dart (`lib/services/email_templates.dart`) e andrebbero portati in TypeScript con il pattern già usato per i certificati (`functions/src/certificateEmailTemplates.ts` + test "drift guard").

- **`CourseType.label` deprecato** (`lib/types/course_type.dart`): sostituire gli usi con il nuovo meccanismo di etichettatura della tipologia.
  - Uso attuale da migrare: `lib/components/course_preview_card.dart` (`widget.course.courseType.label`).
- **Tipologia corso: doppio binario `tags` + `courseType`**: il modello `Course` mantiene sia `tags` (legacy, accesso per tag) sia `courseType` (enum `open` / `personal_trainer`). Consolidare sul solo `courseType` e valutare la deprecazione/rimozione di `tags` dove non più usato.
- **Test E2E da riallineare al nuovo modello** (`integration_test/`, attualmente in `skip: true`):
  - `helpers/seed.dart` genera i corsi di test usando ancora `tags` per la tipologia (`buildTestCourseName` / `createFerragostoTestCourse`): passare a `courseType`.
  - Rivalidare `subscribe_to_course_test.dart` e `waitlist_swap_test.dart` con `getCourseState` aggiornato dopo il merge di `main`.
