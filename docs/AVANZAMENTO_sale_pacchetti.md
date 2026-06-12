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
| `200a444` | **PR4.5** | Ambiente di test locale (Emulator Suite): config emulatori + `.firebaserc`, wiring `--dart-define=USE_EMULATOR` in main.dart (OneSignal spento in emulazione), seed sintetico (`npm run seed:emulator`, shape dal compilato), convention guard import modulari `firebase-admin/firestore` (bug runtime emulatore trovato dallo smoke E2E). Analisi/decisione ambienti in `docs/AMBIENTI_DI_TEST.md` (C=staging target) |
| *(PR5)* | **PR5** | Admin enrollment server-side: `unsubscribeFromCourse` con semantica ADMIN (actor≠target → rimborsa SEMPRE, `confirmedNoRefund` ignorato, niente cancelledEnrollments, `decideAdminRefund`); callable `deleteCourse` (UNA transazione atomica: rimborsi da registro consumi legacy+abbonamento con clamp, waitlist pulita, niente email — fix del legacy N+2 transazioni); callable `recountCourseSubscribed` (ricalcolo dalla fonte di verità — fix `removeUserFromCourse` legacy che non decrementava `subscribed`); retention 90gg + pruning del registro consumi (`atMillis`); client admin → thin wrapper; rimosso `notifyWaitlistUsers` client (dead); **categoria C consegnata**: test integrazione su Emulator Suite reale (`npm run test:integration`, 6 test: round-trip, concorrenza capienza, concorrenza limite settimanale, deleteCourse atomico, recount, authz) + job `functions-integration` in CI |
| *(PR6)* | **PR6** | `firestore.rules` nel repo + blocco `firestore` in firebase.json (l'emulatore le carica: QA manuale realistico). **Lockdown field-level basato su `diff().affectedKeys()`**: self → whitelist campi profilo (isActive solo auto-disattivazione); Admin → anagrafica gestionale MA MAI i server-owned (courses/waitlistCourses/activeSubscriptions/enrollmentConsumption/cancelledEnrollments/uid/email/createdAt); Trainer → solo anagrafica di utenti User; registrazione self vincolata al profilo-prova standard (no auto-crediti/ruoli); corsi: create Admin/Trainer con contatori azzerati, update senza subscribed/waitlist (Trainer solo propri), delete solo callable; subscriptions read-self/write-server-only. DECISIONE: rules field-level + **updateUser DIFF-BASED** (invia solo i campi cambiati vs original, confronto per-giorno su date/set sui tag) INVECE della callable adminUpdateUser — il payload completo includeva chiavi aggiunte/Timestamp rinormalizzati in `affectedKeys` e avrebbe NEGATO il salvataggio del proprio profilo (blocker del 1° gate, risolto); `users.role` ora affidabile (nessuna auto-promozione). create-self vincolata con `hasOnly` (no tag-premium/trial-esteso/entrateSettimanali auto-grantabili); Trainer crea solo User; corsi: Trainer create solo propri + no riassegnazione trainerId; regolamentoAccettatoIl protetto. registration.dart scrive la shape canonica completa. Client: rimosso cancelledEnrollments da updateUser, rimosso deleteUser.dart. `updateUser` diff-based estratto in `buildUserUpdateDiff` PURO + `test/updateUser_test.dart`; fix robustezza: campo entrate svuotato non azzera il credito. DECISIONE documentata: la create manuale dei Trainer NON vincola tag/entrate (flusso gestionale legittimo; i doc manuali hanno id≠auth-uid → non loggabili). **Categoria D consegnata**: suite @firebase/rules-unit-testing (30 test integrazione totali: payload REALI su doc registration-shaped legacy, escalation negati, regolamento self-only) |

Verifica: `flutter analyze` pulito, **flutter test 250/250**, **functions 210/210 jest** + **30/30 integrazione su emulatore** (callable + rules) + `tsc` ok. Gate multi-agent per ogni PR (PR6: 4 passate — blocker payload-completo → fix updateUser diff-based + unit test; major rules create chiusi/documentati; 4° gate PASS pulito).

## Stato production-safe (IMPORTANTE)

Fino a PR3 il committato non cambiava comportamento osservabile. **Con PR4 il
comportamento cambia**: le scritture enrollment passano dal server e la UI di
assegnazione abbonamenti è attiva per gli Admin.

✅ **Vincolo di sequenza risolto**: il write-path server applica eligibility +
decremento per il modello multi-abbonamento, quindi `assignSubscription` può
andare in produzione **insieme** a PR4.

⚠️ **ORDINE DI DEPLOY DEL BLOCCO PR3–PR6 (critico)**:
1. `firebase deploy --only functions` (le callable devono esistere prima del client);
2. pubblicazione build web nuova (merge su `release`);
3. **per ULTIME** `firebase deploy --only firestore:rules` — le rules bloccano
   le scritture dirette del VECCHIO client: vanno deployate solo quando la web
   nuova è online (le tab aperte sulla vecchia versione si romperanno sulle
   scritture finché non ricaricano: accettabile, comunicarlo).
PR4+PR5 functions vanno deployate insieme (retention registro consumi).

✅ **Caveat admin interim PR4→PR5 RISOLTO** (PR5): i flussi admin sono
server-side, rimborsano sempre (anche `remainingEntries` via registro consumi)
e `confirmedNoRefund` è ignorato per le operazioni su altri utenti.

⚠️ **Caveat residuo — modello misto** (crediti legacy residui + abbonamento
attivo di un'altra famiglia): finché esiste UNA voce viva nello snapshot, i
corsi delle famiglie non coperte risultano non idonei (i crediti legacy non
vengono usati come fallback per-famiglia). Decisione di prodotto rimandata
(PR7 o memo): nell'interim, all'assegnazione di un abbonamento conviene
azzerare/convertire i crediti legacy residui dell'utente.

## Prossimi step (DA FARE)

### Staging (opzione C — ⭐ target, prima del rilascio in prod)

Da fare prima di rilasciare il blocco PR3–PR6 in produzione (vedi
`docs/AMBIENTI_DI_TEST.md` per il dettaglio): progetto Firebase gemello su
Blaze (⚠️ serve Francesco per progetto/billing), parametrizzazione
`ONESIGNAL_APP_ID` (oggi hardcoded in `functions/src/handler.ts` e
`lib/main.dart`) + seconda app OneSignal, `flutterfire configure` per il
secondo `firebase_options` + switch `--dart-define=ENV=staging`, alias
`.firebaserc`, seed sintetico (MAI dati reali: GDPR).

### PR7 — UI polish + docs + cleanup
- HomePage: card multi-abbonamento (residui/frequenza/scadenza per abbonamento); estendere `getTipologiaIscrizioneLabel` (famiglie + "illimitato"); dashboard; lista abbonamenti in UserDetailPage.
- Riscrivere/estendere `README_ISCRIZIONI.md` col flusso server-side; cleanup eventuale percorso legacy.

## Processo di verifica (consolidato)

Per ogni PR: implementa → `flutter analyze` + `flutter test` (+ `npm run build`/`npm test` in `functions/`) → commit (l'hook esegue flutter+jest) → gate `Workflow({scriptPath:'.claude/workflows/verifica-pr-fitrope.js', args:{base,head,label,tier,spec}})` → fix di blocker/major → amend.

## Note ambiente

- Node 20 richiesto; `nvm default 20` + symlink `/usr/local/bin/{node,npm,npx}` → v20.18.1 (vecchio v4 in `node-v4.0.0.bak`).
- Hook `.git/hooks/pre-commit` (repo principale, condiviso tra worktree): fa `unset GIT_DIR …` per non rompere il `git describe` di Flutter. Non versionato → riapplicare se si clona da zero.
- `functions/lib/` (compilato) è tracciato ma in parte gitignored: non committare la sua churn (si rigenera al deploy via predeploy `tsc`).
