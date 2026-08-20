# Piano — Documento "Aree di test" FitRope (dual-target: locale + staging)

**Branch**: `fgrotta/test-areas-catalog`, creato da `origin/develop` (`cc5fbeb`, che già contiene in squash il lavoro precedente su documentazione + email certificati). PR con base `develop` sul fork `fgrotta/fitrope_app`.

**Vincolo di workspace/base**: questo piano appartiene al workspace `test-areas-catalog` e deve restare basato su `develop`. Non creare la PR con base `origin/fgrotta/staging-environment`: quel branch è un antenato già confluito in `develop` e farebbe comparire nel diff decine di modifiche estranee al documento.

## Context

Il repo ha già 631 casi automatici nelle suite Dart/Jest conteggiate sotto, ma distribuiti in modo molto sbilanciato (numeri verificati su `cc5fbeb`; il totale non include i 4 scenari dichiarati in `integration_test/`, di cui 2 attivi ma fuori CI e 2 skippati):

- `test/` — 29 file, 326 casi Dart unit/widget (logica di enrollment, stati, serializzazione, label)
- `functions/src/__tests__/` — 13 suite, 272 casi Jest (handler, eligibility, refund, notifiche, gate ambiente degli export)
- `functions/src/__integration__/` — 2 file, 33 casi su Emulator Suite (callable reali, rules, concorrenza)
- `integration_test/` — **quasi vuoto**: 1 file login con 2 casi attivi, più 2 casi (`subscribe_to_course_test.dart`, `waitlist_swap_test.dart`) con `skip: true`; l'helper corrente punta alla **produzione**, non all'emulatore

Nessun workflow CI esegue `integration_test/`. Il risultato è che il livello dove l'utente vive — la UI end-to-end — è di fatto non coperto, e aree intere (corsi ricorrenti, dashboard admin, creazione utente) non hanno **nessun** test a nessun livello.

L'utente chiede: una **lista completa delle aree di test**, con la premessa che i test debbano poter girare sia in locale sia contro staging (<https://fgrotta.github.io/fitrope_app/>).

**Deliverable di questo intervento: solo il documento** (decisione utente). Nessun codice di test, nessuna `Key()`, nessuna modifica ai workflow. Il documento è però la specifica esecutiva di quel lavoro, quindi include architettura, fixture, selettori da aggiungere e gate CI in modo che le PR successive siano meccaniche.

## Decisioni prese con l'utente

1. **Dual-target = due binari.** Suite principale: `integration_test/` Flutter in Chrome, puntato al backend locale (Emulator Suite) **oppure** al backend staging (`APP_ENV=staging`) — stesso codice sorgente da cui è buildato il sito Pages, esercita rules e callable reali. In più un **piccolo smoke Playwright** sull'URL deployato, per coprire il rischio "artefatto pubblicato" che il binario Flutter non vede.
2. **Sì alle `Key()` in produzione** dove servono per test robusti (oggi ne esistono 5 in tutta l'app).
3. **Registrazione testata completa su entrambi i target, orchestrata in due fasi.** La prima invocazione `flutter drive` registra un indirizzo univoco e asserisce account/documento + blocco login non verificato; il runner host esegue poi lo script Admin SDK che marca **quello stesso UID** come `emailVerified: true`; una seconda invocazione completa il login. Il runner cancella infine account Auth + documento Firestore con `if: always()`. Non si pre-crea l'account, perché ciò renderebbe il happy path un caso “email già in uso”; il browser Flutter non può invocare direttamente l'Admin SDK host, quindi la separazione in due target è intenzionale.

## Il documento da scrivere

**File nuovo: `docs/AREE_DI_TEST.md`.** Complementare a `docs/AMBIENTI_DI_TEST.md` (che descrive *dove* si testa); questo descrive *cosa* si testa e *a quale livello*. Aggiungere un rimando in `CLAUDE.md` nella sezione comandi/test e un rimando reciproco in `docs/AMBIENTI_DI_TEST.md`.

Struttura, in italiano come il resto della documentazione:

### 1. Scopo e come si legge
Mappa delle 7 aree citate dall'utente sulle aree del catalogo: 1→A1, 2→A4+A5, 3→A6+A7, 4→A8+A9, 5→A10, 6→A14, 7→A12.

### 2. Architettura dual-target
Tabella dei tre binari, con comandi concreti:

| Binario | Cosa esercita | Comando |
|---|---|---|
| Locale (emulatore) | rules + callable reali, dati sintetici, isolato, distruttivo permesso | build Functions (`cd functions && npm ci && npm run build`), avvio in un processo separato con `firebase emulators:start --project fit-rope-app-1f575`, seed con `cd functions && npm run seed:emulator`, poi un `flutter drive` per scenario: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<scenario>.dart -d chrome --dart-define=USE_EMULATOR=true --dart-define-from-file=integration_test/test_env.emulator.json` |
| Staging (backend reale) | progetto `fit-rope-staging`, indici compositi, Cloud Run reale, OneSignal in allowlist | un `flutter drive` per scenario con `--dart-define=APP_ENV=staging`, tutti i define `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_AUTH_DOMAIN`, `FIREBASE_STORAGE_BUCKET`, `FIREBASE_MEASUREMENT_ID` e `--dart-define-from-file=integration_test/test_env.staging.json` generato nel job CI |
| Smoke deployato | l'artefatto su GitHub Pages (bundle, base-href, service worker, banner STAGING) | Playwright su `https://fgrotta.github.io/fitrope_app/` |

Punti da documentare esplicitamente:
- Il **`--project fit-rope-app-1f575` obbligatorio** sull'emulatore (trappola già in `CLAUDE.md`: Auth segrega gli account per progetto, il login fallisce con "Email o password sbagliati").
- Su web gli `integration_test` **non** si eseguono con `flutter test -d chrome`: servono `flutter drive`, `test_driver/integration_test.dart`, un solo `--target` per invocazione e chromedriver sulla porta 4444. Un runner futuro può ciclare i file, ma deve preservare questi argomenti.
- `test_env.emulator.json` contiene solo credenziali sintetiche committabili (`test1234`); `test_env.staging.json` viene generato nel job dalle fixture staging e non viene committato. Correggere contestualmente i riferimenti obsoleti a `flutter test` in `integration_test/test_env.example.json` e `integration_test/fixtures/test_users.dart`.
- Flutter web renderizza su canvas → Playwright **non** può fare asserzioni sulla UI senza abilitare l'albero semantics; per questo lo smoke resta volutamente sottile (caricamento, `version.json`, `flutter_bootstrap.js`, assenza di errori console, banner STAGING via semantics) e **non** duplica i flussi funzionali.
- Ogni test contro staging deve avere `concurrency` in CI condiviso con `staging-deploy`, altrimenti gira mentre `seed:staging` riscrive le fixture sotto i piedi.
- Ogni risorsa dinamica staging usa un namespace univoco `[TEST:<github.run_id>:<attempt>]`. `addTearDown` effettua il cleanup dopo essersi ri-autenticato come Admin, ma non è sufficiente contro crash/cancellazioni: il job deve avere anche uno step amministrativo `if: always()` e una raccolta iniziale delle fixture `[TEST:*]` scadute.
- Il `launchTestApp()` attuale (`integration_test/helpers/test_app.dart`) inizializza **`DefaultFirebaseOptions` = produzione**: va rifattorizzato per riusare la stessa inizializzazione ambiente di `main.dart`, collegare Auth/Firestore/Functions agli emulatori prima del primo accesso e rifiutare configurazioni staging incomplete. È il blocco #1.
- Lo stesso helper deve accettare `resetSession: true` (default isolamento) oppure `false` (test splash/persistenza), azzerare esplicitamente store/cache tra i casi e lasciare OneSignal disattivato salvo test dedicati con facade sostituibile.

### 3. Livelli e criterio di assegnazione
Regola da enunciare: la logica pura resta unit (Dart `test/` + Jest `__tests__`), le transazioni/rules restano su Emulator Suite (`__integration__`), la UI end-to-end va in `integration_test/`, e **non si duplica** a livello E2E ciò che è già dimostrato a livello unit — l'E2E verifica il *cablaggio* (finder → callable → stato → render), non la matrice di business.

### 4. Fixture e seed
- Emulatore: i 6 utenti di `seedEmulator.js` (password `test1234`) coprono i modelli legacy pacchetto/mensile/prova, un percorso multi-sub `FREQUENCY` Open 3x e un percorso `ENTRIES` Hyrox, più admin e trainer. Non coprono ancora PT: aggiungere a `abbonato-test` una subscription deterministica `pt_10i_3m`. Le varianti Open 2x/illimitato restano nella matrice unit; l'E2E usa Open 3x come rappresentante del billing `FREQUENCY`.
- Staging: `stg_admin` / `stg_trainer` / `stg_member` + i 3 doc subscription deterministici. **Manca un secondo utente base** (`stg_member2`) — indispensabile per lo swap di waitlist (A10) e per i test "admin agisce su un altro utente" (A9, A12). Da aggiungere a `seedStaging.js`.
- Corsi dinamici E2E: sostituire `ferragostoSlot()` con uno slot univoco nei successivi 7–14 giorni, sempre compreso nella validità delle subscription seed. Il 15 agosto dell'anno successivo rende oggi i test `EXPIRED` e non può essere riusato.
- Registrazione A1: runner host con operazioni Admin SDK `findAuthUidByEmail`, `markEmailVerified(uid)` e `deleteSignupProbe(uid)`. Ordine fisso: `registration_unverified_test.dart` → lookup/verifica dello stesso UID → `registration_verified_login_test.dart` → cleanup `if: always()`. Su staging lo script usa lo stesso access token federato di `seedStaging.js`; sull'emulatore usa `FIREBASE_AUTH_EMULATOR_HOST`/`FIRESTORE_EMULATOR_HOST`.
- Nota notifiche: staging ha `pushNotificationsEnabled: false` e allowlist email. L'emulatore usa una REST key OneSignal fittizia e verifica soltanto export/callable/payload/soppressione; l'unica consegna email reale ammessa è A16b su staging verso un destinatario `stg_` esplicitamente allowlisted.

### 5. Catalogo delle aree di test  ← nucleo del documento

Per ogni area: sotto-casi, livello di test, **stato di copertura attuale** (con i file esistenti citati per path), target (locale / staging / entrambi) e blocchi noti.

- **A1 Registrazione utente** — validazioni form (email vuota, password <6, mismatch, nome/cognome <2, telefono ≠10 cifre, privacy non accettata), happy path → "Email di conferma inviata!", shape canonica del doc `users/{uid}` (`ABBONAMENTO_PROVA`, `entrateDisponibili: 1`, `role: 'User'`, `tipologiaCorsoTags: ['Open']`, `fineIscrizione` +30g@23:59), rules self-create che rifiutano campi extra/role diverso, email già in uso, login bloccato prima della verifica ("Email non verificata" + 'Invia di nuovo email'), verifica Admin SDK dello stesso UID e login riuscito nella seconda fase. *Coperto*: rules in `firestoreRules.integration.test.ts`. *Gap*: validazioni form e E2E bifase.
- **A2 Login / logout / sessione** — credenziali valide, sbagliate ("Email o password sbagliati"), utente disattivato, email non verificata, password dimenticata, logout+restart, splash con redirect, `isLogged()` che richiede `emailVerified`. *Coperto parziale*: `integration_test/login_test.dart` (2 casi).
- **A3 Autorizzazione, ruoli, navigazione** — nav items per ruolo (User / Trainer senza Utenti-Dashboard / Admin), dashboard desktop-only, accesso diretto a `/course-management` come User → accesso negato/redirect senza renderizzare il form, `UserDetailPage` altrui → 'Accesso Negato', gating icone delete/edit corso, Admin e Trainer non possono iscriversi. *Coperto*: lato server. *Gap*: tutto il gating UI.
- **A4 Creazione corso singolo** — happy path su tutti i campi (nome, data, ora, durata, capacity, trainer, sala, `courseType`, `imageKey`, `tags`, `reminderEnabled`, `waitlistEnabled`), validazioni (nome vuoto, data mancante, corso nel passato, durata ≤0, capacity ≤0), Trainer con auto-assegnazione e senza dropdown trainer, modalità edit (durata nascosta, `subscribed`/`waitlist` strippati dal payload) e duplicate, rules su `subscribed != 0` e `trainerId != auth.uid`. *Coperto*: `create_course_test`, `update_course_test`, `course_flags_test`, `course_sala_serialization_test`. *Gap*: E2E.
- **A5 Corsi ricorrenti** — selezione giorni, range date, generazione N corsi, validazioni (inizio>fine, oltre 5 mesi, nessun giorno, nessuna data valida). **Gap totale: zero test a qualsiasi livello.**
- **A6 Visualizzazione corsi — Calendario** — toggle mese/settimana e default per breakpoint, marker giorni, header giorno + pill conteggio, filtri tag e reset al cambio giorno, raggruppamento per `courseType`, masonry 1–3 colonne, empty states, cache 1 minuto di `getAllCourses`, esclusione corsi oltre 150 giorni, compatibilità documenti corso. Comportamento atteso: accettare sia documenti canonici con `uid` sia legacy con solo `id`, e saltare/segnalare solo quelli privi di entrambi; l'attuale filtro preventivo su `id` in `get_courses.dart:33` è un bug da correggere, non un'invariante da proteggere. *Coperto parziale*: `capacity_color_test`, `course_card_widget_test`.
- **A7 Visualizzazione corsi — Home** — "I miei corsi" (solo futuri), sezione "Lista d'attesa", card abbonamento nei tre casi (multi-sub / legacy / nessuno), banner certificato in scadenza, empty state. *Coperto*: `subscription_labels_test`, `subscription_plans_test`. *Gap*: E2E.
- **A8 Iscrizione — tutte le tipologie** — un E2E per percorso sostanzialmente diverso: `ABBONAMENTO_PROVA`, `PACCHETTO_ENTRATE`, temporale, sub `FREQUENCY` (Open 3x rappresentativo; 2x/illimitato restano unit), sub `ENTRIES` Hyrox, sub `ENTRIES` PT, tipo senza famiglia (Hey Mamma), admin `force`. Più: gate regolamento alla prima iscrizione, stati non tappabili (`FULL`, `LIMIT`, `SUBSCRIBE_LIMIT`, `EXPIRED`, `NULL`, `CLOSED` con bottone nascosto). I 7 mapping `REASON_TO_HTTP`, limite settimanale per famiglia, doppio tap e contesa sull'ultimo posto restano unit/integration salvo un solo E2E rappresentativo del rendering errore. La divergenza week-bounds non va congelata: il comportamento atteso è una settimana Europe/Rome coerente tra client e server, con test di boundary domenica/lunedì e DST. *Coperto molto bene*: `active_subscriptions_state_test`, `course_state_edge_cases_test`, `eligibility.test.ts`, `enrollmentHandlers.test.ts`, concorrenza in `enrollment.integration.test.ts`. *Gap*: E2E UI (test `skip: true`).
- **A9 Disiscrizione — finestre e rimborsi** — fuori finestra (rimborso sempre), entro 8h entries/prova, entro 4h frequency/temporale, annulla dialog, `failed-precondition` senza conferma → richiamo della variante force, `kind: NONE` (libera solo il posto), ledger che restituisce la fonte effettivamente debitata con clamp al massimo del piano, admin che rimuove un altro utente (rimborso sempre, `confirmedNoRefund` ignorato), self-unsubscribe su corso iniziato bloccato. *Coperto*: `course_unsubscribe_test`, `refund.test.ts`, `adminHandlers.test.ts`. *Gap*: E2E.
- **A10 Lista d'attesa** — join (dialog → `IN_WAITLIST`, scritture su entrambi i lati), rifiuti (`waitlistEnabled: false`, corso non pieno, già iscritto, duplicato, non eleggibile perché i limiti bloccano la waitlist, corso iniziato, corso riprogrammato), Admin/Trainer esclusi, leave con self-heal delle inconsistenze one-sided, **swap completo** (user1 esce → `notifyWaitlistUsers` → user2 vede `WAITLIST_SPOT_AVAILABLE` → si iscrive e viene rimosso dalla waitlist nella stessa transazione), rimozione dei legacy-scaduti dalla waitlist, rimozione manuale dalla card admin, `deleteCourse` che pulisce senza inviare email. *Coperto*: `waitlist_state_test`, `waitlist_operations_test`, `enrollment.integration.test.ts:339`. *Gap*: E2E (test `skip: true`).
- **A11 Gestione corso lato staff** — lista iscritti espandibile, `AddSubscriberDialog` (solo attivi non già iscritti), rimuovi iscrizione, correggi conteggio → `recountCourseSubscribed`, elimina corso **solo come Admin** (atomico, rimborsi per corsi futuri e **nessun** rimborso per corsi già iniziati; Trainer negato), duplica/modifica secondo i permessi di ruolo, masking dei nomi anonimi. *Coperto*: `course_correction_test`, `adminHandlers.test.ts`. *Gap*: E2E.
- **A12 Admin — ricerca utenti e modifica** — ricerca free-text nome+email, i 4 filtri (tag, tipologia, stato, scadenza abbonamento solo Admin), paginazione 20 con infinite scroll, DataTable desktop vs ListView mobile, azioni riga (Dettagli, Modifica, reset password, Disattiva/Attiva), `UserDetailPage` in edit con permessi per campo (Admin tutto / Trainer solo Nome-Cognome-Telefono-Anonimo su `role == 'User'` / self il proprio sottoinsieme), `updateUser` diff-based contro `diff().affectedKeys()` delle rules, validazioni di salvataggio, campi vietati che devono essere negati, soft delete self, storico iscrizioni/disiscrizioni con dialog "Informazioni disiscrizione". *Coperto*: `update_user_test`, `get_users_test`, `firestoreRules.integration.test.ts`. *Gap*: E2E.
- **A13 Admin — creazione utente** — campi e default di `CreateUserPage`, dropdown Ruolo solo per Admin, utente "senza accesso" (email vuota → `'-'`, doc con id random, **nessun account Auth creato pur accettando una password**), regex email, password ≥6, telefono 10 cifre, e il bug noto della mutazione della lista condivisa `CourseTags.defaultUserTags`. **Gap totale.**
- **A14 Admin — dashboard di monitoraggio** — guard desktop-only, sezione Utenti (totale attivi, nuovi 7/30 giorni, chart per tipologia, chart per famiglia con conteggio multi-famiglia), sezione Corsi (corsi 6 mesi, corsi al completo, tasso di riempimento medio), sezione Abbonamenti (distribuzione, sub-chart per tag, in scadenza 30 giorni, crediti medi residui), sezione Abbonamenti senza data di fine, `UserListDrawer` (apertura da metric row, ricerca su nome/email/telefono, tap → dettaglio), stato di errore con 'Riprova'. **Gap totale: nessun aggregato ha test.** Documentare il gap già noto: i KPI "in scadenza" sono legacy-only e ciechi sugli utenti convertiti a multi-subscription.
- **A15 Abbonamenti — assegnazione** — `AssignSubscriptionCard` solo Admin, catalogo (Open 3 frequenze × 4 durate, Hyrox e PT 10 ingressi × 4 durate), max 1 sub attiva per famiglia → `already-exists`, piano sconosciuto → `invalid-argument`, non-Admin → `permission-denied`, ricalcolo dello snapshot `activeSubscriptions`, label di stato ("Scade oggi" / "1 giorno" / "Valido" / "Scaduto" / "Esaurito"). *Coperto*: `assignSubscription.test.ts`, `user_subscription_test`, `subscription_labels_test`. *Gap*: E2E.
- **A16 Notifiche** — promemoria prova alle 19:00 Europe/Rome del giorno prima e solo con `reminderEnabled`, email "posto disponibile" con `waitlistEnabled` + `emailNotificationsEnabled`, soppressione staging (solo UID `stg_` con email in `STAGING_NOTIFICATION_EMAIL_ALLOWLIST`, prefisso `[STAGING]` nel subject), garanzia server-side dell'alias OneSignal (`ensureOneSignalEmailSubscription`) prima di ogni invio email, preferenze utente `emailNotificationsEnabled`/`pushNotificationsEnabled`. *Coperto*: `handler.test.ts`, `notify.test.ts`, `notifyOrchestration.test.ts`, `email_templates_test`.
- **A16b Email certificati medici — area con gate d'ambiente** (sotto-area distinta perché il suo comportamento *dipende dal target*). `sendTestCertificateEmail` (callable di test) e `certificateEmailsDaily` (`onSchedule` 08:00 Europe/Rome → `runCertificateEmails`: promemoria a −10 giorni e avviso il giorno della scadenza) sono **export condizionali** in `functions/src/index.ts`: esistono **solo** con `APP_ENV=staging` o `FUNCTIONS_EMULATOR=true`, e in produzione l'export è `undefined` così la discovery della CLI non le deploya. Casi: presenza/assenza degli export per ambiente, no-op difensivo se invocate fuori ambiente, finestre-giorno Europe/Rome, selezione destinatari, payload. *Coperto*: `indexExports.test.ts` (gate ambiente via `jest.isolateModules`), `certificateEmails.test.ts` (25 casi), assert di presenza nello `smoke-test` di `staging.yml`. **Dual-target**: sull'emulatore si verifica il percorso callable e il contratto senza pretendere consegna (la key è fittizia); solo su staging `sendTestCertificateEmail` può effettuare una consegna reale verso un UID `stg_` e un'email in allowlist. La callable prova il percorso manuale/template, non sostituisce il test unit della selezione scheduler. Un E2E contro produzione deve fallire perché gli export non esistono.
- **A17 Regolamento e certificato medico** — gate del regolamento alla prima iscrizione, accettazione self-only, banner "in scadenza" (rosso ≤3 giorni), card admin "Certificati in Scadenza". *Coperto*: rules. *Gap*: UI.
- **A18 Preferenze notifiche (self)** — toggle email e persistenza possono avere un E2E web; toggle push, soft prompt/help iOS e rollback su errore OneSignal vanno verificati come widget test con facade OneSignal sostituibile, perché `launchTestApp` disabilita intenzionalmente l'SDK e il push native resta fuori dal target Chrome. *Coperto*: `notification_preferences_test`. *Gap*: widget/fake per gli errori SDK + un E2E web per il salvataggio Firestore.
- **A19 Piattaforma / non funzionale** — breakpoint responsive (mobile <600, tablet <900, desktop <1600, largeDesktop ≥1600), localizzazione `it_IT` e DST Europe/Rome, assenza di layout shift nelle card (lezione già documentata in `CLAUDE.md`), banner STAGING, cache PWA / service worker e header `.htaccess` (solo prod Hostinger), **indici compositi Firestore — non coperti dall'emulatore, verificabili solo su staging**, smoke del sito deployato (`index.html`, `version.json`, `flutter_bootstrap.js`, `firebase functions:list` con assert sulle callable). *Coperto parziale*: job `smoke-test` di `staging.yml`, `italian_time_test`.
- **A20 Regressioni note / anti-drift** — `toJson`/`fromJson` per ogni campo aggiunto (regola `CLAUDE.md`), guardia sulle import `firebase-admin/firestore` (`conventions.test.ts`), gate d'ambiente degli export di `index.ts` (`indexExports.test.ts`), compatibilità `Course` (`uid` canonico, `id` legacy, rifiuto controllato solo se mancano entrambi), doppio binario `tags` + `courseType`, tolleranza di `FitropeUser.fromJson`. Regola da enunciare: ogni divergenza **voluta** tra ambienti deve avere un test che la asserisce; i drift accidentali (es. week-bounds o filtro `id`) vanno invece corretti e coperti sul comportamento desiderato.

### 6. Selettori da aggiungere
Inventario di partenza: in tutta l'app esistono **5 `Key()`** (`login-email-field`, `login-password-field`, `login-submit-button`, `course-card-<uid>`, `course-action-button-<uid>`) più un `ValueKey(course.uid)`. Tutto il resto (pagine admin, form, dialog, chip filtro, celle calendario, card abbonamento) è raggiungibile solo per testo italiano visibile, tooltip o `find.byType`.

Il documento propone una **convenzione di naming** (`<area>-<elemento>[-<id>]`, kebab-case, es. `registration-email-field`, `admin-users-search-field`, `course-form-capacity-field`, `dashboard-metric-<slug>`, `subscription-card-<planKey>`) e la lista dei file da toccare per area: `registration_page.dart`, `course_management_page.dart`, `recurring_course_page.dart`, `admin_users_page.dart`, `admin_dashboard_page.dart`, `user_detail_page.dart`, `create_user_page.dart`, più i dialog condivisi (`course_unsubscribe_helper.dart`, `waitlist_ui_helper.dart`, `AddSubscriberDialog` in `course_card.dart`). I tooltip già esistenti (`'Dettagli'`, `'Modifica'`, `'Elimina corso'`, `'Correggi conteggio iscritti'`, …) restano validi come finder e non vanno duplicati con key.

### 7. Gate CI proposti
- `ci.yml` (PR): invariato + eventuale job E2E su emulatore, sui soli flussi critici (A2, A8, A9, A10).
- `staging.yml`: nuovo job E2E post-`smoke-test`, `environment: staging`, dentro il `concurrency: staging-deploy`, con `STAGING_PROJECT_ID` dichiarata **per job** (trappola già documentata) e chromedriver installato.
- Job smoke Playwright sull'URL Pages, sostituto/estensione dei `curl` attuali.
- Regola di ordine: l'E2E staging gira **dopo** `deploy-rules`, perché è l'unico momento in cui il sito, le callable e le rules sono coerenti.
- Il job E2E crea `test_env.staging.json` durante l'esecuzione, usa il namespace del run, esegue cleanup Admin SDK con `if: always()` e non affida la pulizia soltanto a `addTearDown`. Questo è obbligatorio perché `cancel-in-progress: true` può interrompere il processo Dart prima dei teardown.

### 8. Vincoli e cosa resta fuori
Emulatore cieco su indici compositi, consegna OneSignal/email, push native e comportamento reale di Cloud Run (già in `docs/AMBIENTI_DI_TEST.md`); Playwright cieco sulla UI canvas finché lo smoke non abilita semantics; consegna email reale consentita solo per A16b su staging e destinatario allowlisted; `createUser` gestionale che non crea l'account Auth; `runCertificateEmails` non deployata in produzione ma presente in staging/emulatore; E2E staging distruttivi solo su risorse namespaced e ripulibili amministrativamente.

### 9. Roadmap in PR
Ordine consigliato, con dipendenze:

1. **Runner sicuro** — estrarre/riusare il bootstrap ambiente di `main.dart`; parametrizzare `launchTestApp` su emulatore/staging e `resetSession`; aggiungere i file credenziali target; correggere tutti i comandi a `flutter drive`; fallire chiuso se staging è incompleto, senza fallback a produzione.
2. **Fixture e cleanup** — `stg_member2`, PT nell'emulatore, corsi dinamici nei successivi 7–14 giorni, namespace per run, login Admin prima di `deleteCourse`, script cleanup iniziale/finale `if: always()`, orchestratore host bifase per verificare/eliminare l'account A1.
3. **Selettori** — `Key()` e convenzione, più test widget dove la logica non richiede backend.
4. **Riattivazione critica locale** — adattare i due test `skip: true` alle nuove date/fixture e validarli prima solo su emulatore; poi A1–A3 e A8–A10.
5. **Copertura gestionale** — A4–A5 e A11, quindi A12–A15; correggere `uid`/`id` e week-bounds Europe/Rome con test prima di considerarli anti-drift.
6. **Presentazione e preferenze** — A6–A7, A14 e A18, mantenendo push/OneSignal dietro facade nei widget test.
7. **Staging e artefatto** — portare il sottoinsieme critico su staging dopo `deploy-rules`, aggiungere Playwright smoke con semantics e integrare i gate CI con cleanup resiliente.

## File toccati

- **Nuovo**: `docs/AREE_DI_TEST.md`
- **Modificati** (solo rimandi, 1–2 righe ciascuno): `CLAUDE.md` (sezione comandi/test), `docs/AMBIENTI_DI_TEST.md` (rimando reciproco)

Nessun file di test, nessun file `lib/`, nessun workflow modificato in questo intervento.

## Verifica

Già eseguita su `cc5fbeb` durante la stesura — i comandi restano il modo di ri-verificare il documento a ogni futura modifica:

| Claim | Comando | Esito |
|---|---|---|
| 29 file / 326 casi Dart | `find test -maxdepth 1 -type f -name '*_test.dart' \| wc -l`; `grep -rhoE '^[[:space:]]*(test\|testWidgets)\(' test/ --include='*.dart' \| wc -l` | ✅ 29 / 326 |
| 13 suite / 272 casi Jest unit | `find functions/src/__tests__ -maxdepth 1 -type f -name '*.test.ts' \| wc -l`; `grep -rhoE '^[[:space:]]*(it\|test)\(' functions/src/__tests__ --include='*.ts' \| wc -l` | ✅ 13 / 272 |
| 2 file / 33 casi integration | stessi comandi su `functions/src/__integration__/` | ✅ 2 / 33 |
| solo 5 `Key()` in tutta l'app | `grep -rn "Key('" lib/ \| wc -l` | ✅ 5 |
| 2 test E2E skippati | `grep -rn "skip: true" integration_test/` | ✅ `subscribe_to_course_test.dart:88`, `waitlist_swap_test.dart:149` |
| gap totale A5 / A13 / A14 | `grep -rlni "recurring\|createuserpage\|admindashboard" test/ functions/src/` | ✅ vuoto |
| `launchTestApp` puntato a produzione (blocco #1) | `grep -n "DefaultFirebaseOptions" integration_test/helpers/test_app.dart` | ✅ riga 21, nessun ramo `USE_EMULATOR`/`APP_ENV` |
| manca un secondo member su staging | `grep -n "stg_" functions/scripts/seedStaging.js` | ✅ solo `stg_admin`, `stg_trainer`, `stg_member` |
| email certificati deployate su staging | `grep -n "certificateFunctionsEnabled" functions/src/index.ts` | ✅ export condizionali + assert nello smoke-test |
| comando web corretto | `sed -n '55,75p' integration_test/README.md`; `flutter drive --help` | ✅ richiede `flutter drive`, driver, target e chromedriver; non `flutter test -d chrome` |
| helper Ferragosto incompatibile con subscription brevi | `sed -n '17,31p' integration_test/helpers/seed.dart`; confronto con seed 3 mesi | ✅ dopo il 15 agosto seleziona l'anno successivo → stato `EXPIRED` |
| cleanup corso Admin-only | `grep -n "requireAdmin" functions/src/enrollment/admin.ts`; controllo actor finale dei due E2E | ✅ `subscribe_to_course_test` termina come member e oggi non può cancellare |
| compatibilità `uid`/`id` da correggere | `sed -n '42,50p' lib/types/course.dart`; `sed -n '30,36p' lib/api/courses/get_courses.dart` | ✅ il modello accetta `uid`, ma il loader scarta ancora i documenti senza `id` |

Dopo la scrittura del documento:

1. Rileggerlo verificando che ognuna delle 7 aree richieste dall'utente sia mappata e rintracciabile.
2. `dart format --set-exit-if-changed .` e `flutter analyze --no-fatal-infos` non sono impattati (solo markdown), ma il pre-commit hook li esegue comunque: farli girare prima del commit.
