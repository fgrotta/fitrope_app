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

Verifica: `flutter analyze` pulito, **flutter test 225/225**, **functions 50/50 jest** + `tsc` ok.

## Stato production-safe (IMPORTANTE)

Tutto il committato **non cambia comportamento osservabile** in produzione:
- nessuno scrive `activeSubscriptions` (snapshot sempre vuoto) → `getCourseState` usa il path legacy;
- la UI di assegnazione è **gated dietro `kDebugMode`**.

⚠️ **Vincolo di sequenza**: `assignSubscription`/UI non devono andare in produzione prima di **PR4** (enforcement + decremento server-side), altrimenti gli ingressi ENTRIES non verrebbero scalati.

## Prossimi step (DA FARE)

### PR4 — subscribe/unsubscribe/waitlist → Cloud Functions  *(il più critico)*
- Portare `lib/api/courses/subscribeToCourse.dart` e `unsubscribeToCourse.dart` (+ join/leave waitlist) in callable TS sotto `functions/src/enrollment/`, riusando `plansCatalog.ts`/`subscription.ts`.
- Transazione: validazione eligibility (frequenza per famiglia / `remainingEntries`), capienza, già-iscritto; incremento `course.subscribed`; decremento `remainingEntries` dell'abbonamento giusto (o `entrateDisponibili` legacy) + aggiornamento snapshot; rimborso con finestre **4h/8h** + `entryLost` + `cancelledEnrollments`; rimozione da waitlist; promemoria prova spostato nel server.
- Client: `lib/api/courses/*` chiamano le callable (pattern `FirebaseFunctions.instanceFor(region:'europe-west8')`); rimuovere le transazioni client.
- **Poi togliere il gate `kDebugMode`** su `AssignSubscriptionCard` (UserDetailPage) + cablare `onAssigned` (reload utente + invalida `user_cache_manager`).
- Test: Jest (logica pura eligibility/decremento + handler con fake Firestore), idealmente emulatore per le transazioni.

### PR5 — admin enrollment server-side
- Portare `deleteCourse`/`removeUserFromCourse`/`forceUnsubscribeFromCourse` (toccano iscrizioni di altri utenti) in Cloud Functions.
- `createCourse`/`updateCourse` restano client per ora → `// TODO(server-migration)`.

### PR6 — firestore.rules nel repo + lockdown  *(ULTIMO PR di scrittura)*
- Portare `firestore.rules` nel repo + blocco `firestore` in `firebase.json` (oggi assenti).
- Lockdown: `subscriptions` write solo server; `users` write client solo campi profilo (DENY `entrateDisponibili`/`fineIscrizione`/`tipologiaCorsoTags`/`activeSubscriptions`/`role`/`courses`); `courses` `subscribed`/`waitlist` solo server (field-level finché create/update restano client).
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
