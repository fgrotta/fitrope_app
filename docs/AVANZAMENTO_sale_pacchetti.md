# Avanzamento — Sale + pacchetti/abbonamenti

Stato della feature "Sale per corso + nuovo catalogo abbonamenti (Open/Hyrox/PT)".
Branch: `fgrotta/sale-pacchetti-abbonamenti` (target `main`).

> Piano dettagliato e analisi alternative: `.context/PIANO_DETTAGLIATO_opzione2.md`
> e `.context/PIANO_sale_pacchetti_abbonamenti.md` (gitignored, nel workspace).

## Decisioni di prodotto (chiuse)

- **Multi-abbonamento**: un utente può avere più abbonamenti attivi insieme.
- Famiglie: **Open** (frequenza 2x/3x/illimitato), **Hyrox** e **PT** (ad ingressi, **10**). Durate **1/3/6/12 mesi**.
- Accesso 1:1 famiglia↔tipologia corso.
- **Sale**: lista chiusa `Sala 1`/`Sala 2`, scelta sul corso. Mappatura tipologia→sala prevista (`CourseType.defaultSala`) ma non attiva.
- Catalogo (sale/tipologie/piani) **in codice**. Prezzi fuori scope. **Nessuna migrazione** dati.

## Architettura scelta (Opzione 2)

- Dominio iscrizioni → **server-side** (Cloud Functions, transazioni atomiche).
- Storage: collezione `subscriptions` (fonte di verità) + **snapshot `activeSubscriptions`** sul doc utente (read-path client veloce).
- `getCourseState` resta client (display); **fallback al modello legacy** quando `activeSubscriptions` è vuoto → zero regressione.
- Lockdown `firestore.rules` come **ultimo** PR di scrittura.

## PR completate (committate, hook attivo, gate-verificate)

| Commit | PR | Contenuto |
|---|---|---|
| `7de7a50` | **PR1** | `Sale`, tag/registry tipologie (`CourseType`), `Course.sala` (+ serializzazione, `copyWith`), selettore sala in CourseManagementPage/RecurringCoursePage, sala in CourseCard |
| `911b3e6` | infra | Gate riutilizzabile `.claude/workflows/verifica-pr-fitrope.js`, subagent `.claude/agents/fitrope-enrollment-reviewer.md`, job `functions-test` in CI |
| `4726f2f` | **PR2** | `SubscriptionFamily`/`BillingMode`, `UserSubscription` + serializzazione resiliente, catalogo `SubscriptionPlans` (12 Open + 4 Hyrox + 4 PT), `FitropeUser.activeSubscriptions`, `CourseType.family`, refactor `getCourseState` multi-abbonamento (scope per famiglia, illimitato, scadenza per-abbonamento, accesso tag OR copertura) |
| `22285e4` | **PR3** | Cloud Function `assignSubscription` (admin, transazione + snapshot, vincolo max 1 attivo/famiglia) + catalogo server TS allineato al client + UI `AssignSubscriptionCard` in UserDetailPage |
| *(PR4)* | **PR4** | Write-path enrollment → Cloud Functions: callable `subscribeToCourse`/`unsubscribeFromCourse`/`joinWaitlist`/`leaveWaitlist` (eligibility autoritativa `eligibility.ts` mirror di `getCourseState`, **valutata in transazione** — limite settimanale non bypassabile da richieste concorrenti; finestre rimborso 8h/4h `refund.ts`; decremento/ripristino `remainingEntries` + snapshot; **registro consumi per prenotazione** `enrollmentConsumption` — il rimborso ripristina la fonte realmente consumata, niente mint/burn nella transizione legacy→abbonamento né con force a credito zero, clamp al max del piano; **voci snapshot scadute escluse dalla selezione del modello** client+server — i crediti legacy non restano bloccati; gate corso-già-iniziato e `waitlistEnabled`; fix bug decremento legacy sui temporali); promemoria prova + notifiche waitlist server-side (`notify.ts`, Europe/Rome, helper TZ testati su DST; niente promemoria prova a utenti convertiti); client Dart → thin wrapper callable (helper condiviso `enrollment_callable.dart`, stesse firme); `CourseUnsubscribeHelper` multi-abbonamento (8h ENTRIES / 4h FREQUENCY); **rimosso gate `kDebugMode`** su AssignSubscriptionCard + `onAssigned` invalida cache; `functions/lib` fuori dal tracking (predeploy `tsc` garantisce build fresca) |

Verifica: `flutter analyze` pulito, **flutter test 232/232**, **functions 168/168 jest** + `tsc` ok. Gate multi-agent tier max passato (fix di tutti i major attuabili; vedi caveat sotto).

## Stato production-safe (IMPORTANTE)

Fino a PR3 il committato non cambiava comportamento osservabile. **Con PR4 il
comportamento cambia**: le scritture enrollment passano dal server e la UI di
assegnazione abbonamenti è attiva per gli Admin.

✅ **Vincolo di sequenza risolto**: il write-path server applica eligibility +
decremento per il modello multi-abbonamento, quindi `assignSubscription` può
andare in produzione **insieme** a PR4 (stesso deploy `firebase deploy --only
functions`; deployare functions PRIMA di pubblicare la build web, così le
callable esistono quando il client le chiama).

⚠️ **Caveat interim PR4→PR5** (dal gate di verifica):
- I flussi admin ancora client (`deleteCourse`/`removeUserFromCourse`/
  `forceUnsubscribeFromCourse`) ripristinano solo `entrateDisponibili` legacy:
  per utenti del nuovo modello NON ripristinano `remainingEntries` (né leggono
  il registro consumi). Fino a PR5: preferire la disiscrizione standard
  (callable, già supporta Admin/Trainer su altri) ed evitare assegnazioni di
  abbonamenti su larga scala prima di PR5.
- **Modello misto** (crediti legacy residui + abbonamento attivo di un'altra
  famiglia): finché esiste UNA voce viva nello snapshot, i corsi delle famiglie
  non coperte risultano non idonei (i crediti legacy non vengono usati come
  fallback per-famiglia). Decisione di prodotto rimandata (PR7 o memo):
  nell'interim, all'assegnazione di un abbonamento conviene azzerare/convertire
  i crediti legacy residui dell'utente.

## Prossimi step (DA FARE)

### PR4.5 — Ambiente di test locale (Emulator Suite)  *(PRIMA di PR5)*

> Analisi completa e decisione: `docs/AMBIENTI_DI_TEST.md`. Deciso il
> 2026-06-10: **opzione C (progetto staging) è il target migliore** ma richiede
> creazione progetto/billing (azione di Francesco) → si implementa SUBITO
> l'opzione A (emulatori locali), C prima del rilascio in prod.

- Config `emulators` in `firebase.json` (Auth/Firestore/Functions/UI) + `.firebaserc`.
- Wiring client: `--dart-define=USE_EMULATOR=true` in `main.dart`
  (useAuthEmulator/useFirestoreEmulator/useFunctionsEmulator sulla region
  `europe-west8`; `EMULATOR_HOST` per device fisici).
- Seed sintetico (`functions/scripts/seedEmulator.js` + `npm run seed:emulator`):
  admin/trainer/utenti legacy+nuovo modello/corsi della settimana.
- `functions/.secret.local` con key OneSignal fittizia (no invii reali).
- Regola operativa: da ora il QA manuale delle feature enrollment si fa
  sull'emulatore, NON in produzione.

### Staging (opzione C — ⭐ target, prima del rilascio in prod)

Da fare prima di rilasciare il blocco PR3–PR6 in produzione (vedi
`docs/AMBIENTI_DI_TEST.md` per il dettaglio): progetto Firebase gemello su
Blaze (⚠️ serve Francesco per progetto/billing), parametrizzazione
`ONESIGNAL_APP_ID` (oggi hardcoded in `functions/src/handler.ts` e
`lib/main.dart`) + seconda app OneSignal, `flutterfire configure` per il
secondo `firebase_options` + switch `--dart-define=ENV=staging`, alias
`.firebaserc`, seed sintetico (MAI dati reali: GDPR).

### PR5 — admin enrollment server-side
- Portare `deleteCourse`/`removeUserFromCourse`/`forceUnsubscribeFromCourse` (toccano iscrizioni di altri utenti) in Cloud Functions: devono ripristinare anche `remainingEntries` (nuovo modello) leggendo il **registro consumi** (`enrollmentConsumption`) + regola "admin rimborsa sempre" del README. Nello stesso PR: quando `actor != targetUserId`, la callable `unsubscribeFromCourse` deve IGNORARE `confirmedNoRefund` e rimborsare sempre (oggi un privilegiato può far perdere il credito a un altro utente passando `confirmedNoRefund:true` — finding security PR4).
- Portare anche `updateCourseSubscribedCount` ("Correggi conteggio" in course_card): scrive `courses.subscribed` dal client con update non transazionale — da PR4 il campo è server-owned, e il lockdown PR6 lo romperebbe. Preferibile ricalcolo server-side.
- `createCourse`/`updateCourse` restano client per ora → `// TODO(server-migration)` (updateCourse già esclude `subscribed`/`waitlist` dal payload).
- **Pruning `enrollmentConsumption`**: oggi le voci dei corsi frequentati (mai disiscritti) restano per sempre sul doc utente — pulizia opportunistica delle voci con corso concluso (allo subscribe/unsubscribe o in un job).
- **Categoria C del piano (test integrazione Firebase Emulator)**: suite emulatore sulle callable (transazioni a 3 doc, atomicità, concorrenza/capienza, retry) — pianificata dal piano §8 per PR3-PR5, NON ancora consegnata (PR4 usa un fake in-memory). Aggiungere `firebase emulators:exec` + jest in CI.

### PR6 — firestore.rules nel repo + lockdown  *(ULTIMO PR di scrittura)*
- Portare `firestore.rules` nel repo + blocco `firestore` in `firebase.json` (oggi assenti).
- Lockdown `users`: **WHITELIST dei soli campi profilo** scrivibili dal client (name, lastName, numeroTelefono, preferenze notifiche, regolamentoAccettatoIl) invece di deny-list. ⚠️ Finding security PR4: il deny-list originario (`entrateDisponibili`/`fineIscrizione`/`tipologiaCorsoTags`/`activeSubscriptions`/`role`/`courses`) NON copre i campi che il server ora usa come input fidati — `enrollmentConsumption` (forgiabile → il server conia entrate legacy all'unsubscribe), `cancelledEnrollments` (svuotabile → bypass del limite settimanale), `tipologiaIscrizione`/`entrateSettimanali` (→ illimitato lato server), `waitlistCourses`. La whitelist li chiude tutti per costruzione.
- `subscriptions` write solo server; `courses` `subscribed`/`waitlist` solo server (field-level finché create/update restano client).
- Valutare `enforceAppCheck` sulle callable enrollment + cooldown per le email waitlist per corso (anti spam/amplificazione, parità col pre-PR4 ma ora centralizzato).
- Test: `@firebase/rules-unit-testing`. **Deve essere dopo PR4/PR5** (altrimenti rompe le scritture client).

### PR7 — UI polish + docs + cleanup
- HomePage: card multi-abbonamento (residui/frequenza/scadenza per abbonamento); estendere `getTipologiaIscrizioneLabel` (famiglie + "illimitato"); dashboard; lista abbonamenti in UserDetailPage.
- Riscrivere/estendere `README_ISCRIZIONI.md` col flusso server-side; cleanup eventuale percorso legacy.

## Processo di verifica (consolidato)

Per ogni PR: implementa → `flutter analyze` + `flutter test` (+ `npm run build`/`npm test` in `functions/`) → commit (l'hook esegue flutter+jest) → gate `Workflow({scriptPath:'.claude/workflows/verifica-pr-fitrope.js', args:{base,head,label,tier,spec}})` → fix di blocker/major → amend.

## Note ambiente

- Node 20 richiesto; `nvm default 20` + symlink `/usr/local/bin/{node,npm,npx}` → v20.18.1 (vecchio v4 in `node-v4.0.0.bak`).
- Hook `.git/hooks/pre-commit` (repo principale, condiviso tra worktree): fa `unset GIT_DIR …` per non rompere il `git describe` di Flutter. Non versionato → riapplicare se si clona da zero.
- `functions/lib/` (compilato) è tracciato ma in parte gitignored: non committare la sua churn (si rigenera al deploy via predeploy `tsc`).
