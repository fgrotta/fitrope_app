# Presenze effettive ai corsi — design e piano

## Contesto

Oggi FitRope sa chi si è *prenotato* a un corso, non chi c'era davvero. Gli ingressi si scalano alla prenotazione e il no-show non esiste come concetto (solo la disdetta tardiva in `cancelledEnrollments`). L'obiettivo di lungo periodo è uno **score di rischio abbandono** per socio: serve un registro durevole e completo di presenze/assenze per utente, non una spunta effimera sul corso.

Decisioni prese in brainstorming (30/09/2026):

- **Scopo**: alimentare lo score futuro. Nessun effetto automatico sul socio oggi (niente penalità, niente ingressi scalati alla presenza). Senza penalità l'incentivo a barare è nullo: la verifica di prossimità è fuori scope, basta la finestra temporale server-side.
- **Chi marca**: il **Trainer a inizio lezione** è la regola (spunta per riga nella lista iscritti della card corso); il **socio** ha un self check-in "Sono in sala"; la reception usa un account Admin (già coperto dal ruolo).
- **Appello**: nessuno presente di default; ogni tocco del trainer scrive subito, nessun "salva"; chi non viene toccato è assente. Un marcatore sul corso distingue "appello mai fatto" da "nessuno presente".
- **Self check-in**: solo `present: true`, da 15 min prima dell'inizio a **30 min dopo l'inizio**. Dopo, il socio vede "Chiedi al trainer di registrare la tua presenza". Se lo staff ha già registrato (presente o assente), il socio non può fare nulla e vede "Presenza già registrata".
- **Staff**: Admin sempre; **Trainer solo sui propri corsi** (`trainerId == uid`, ammesso anche `trainerId` vuoto, come fa già la UI in `calendar_page.dart:637`); da 30 min prima dell'inizio in poi, senza limite superiore; può mettere presente o assente; il tocco staff sovrascrive sempre un self.
- **Storage**: collezione top-level `attendance`, scritta solo dal server.
- **Scartati**: QR rotante/kiosk, scanner in-app (WebKit senza `BarcodeDetector`, permesso camera ricorrente, rischio wasm), geolocalizzazione, IP Wi-Fi (non c'è Wi-Fi soci), **beacon Bluetooth** (Web Bluetooth assente in WebKit quindi zero copertura iOS; su Android Chrome l'ascolto passivo degli advertisement è dietro flag e resta solo `requestDevice()` con dialogo di scelta a ogni uso; BLE attraversa i muri; hardware da gestire; l'unica via per iOS sarebbe un'app nativa negli store, cambio di distribuzione fuori scope).

## Modello dati

`attendance/{courseId}_{userId}` (id deterministico):

```
courseId, userId, courseStartMillis, present: bool,
source: 'self' | 'trainer' | 'admin', markedBy: uid,
markedAt (primo istante, solo su create), updatedAt
```

Marcatore server-owned su `courses/{id}`: `attendance: { lastMarkedAt, lastMarkedBy, presentCount }`. Scritto come oggetto intero in transazione (il fake db dei test non supporta dotted path né `increment`). Aggiornato anche dai self check-in, così `presentCount` è esatto.

Indici: solo single-field (`courseId`, `userId`), nessun composito. Una futura lista "le mie presenze" ordinata richiederà `(userId, courseStartMillis desc)`: segnalarlo nel README.

## Lato server (functions + rules)

### Nuovo modulo `functions/src/enrollment/attendance.ts`

- Costanti: `SELF_WINDOW_BEFORE = 15'`, `SELF_WINDOW_AFTER = 30'`, `STAFF_WINDOW_BEFORE = 30'`, `TRAINER_MAY_MARK_UNASSIGNED_COURSE = true`.
- **Logica pura** `decideAttendance(input) → { allowed, reason, source, noop, presentDelta }` (modello `eligibility.ts`/`refund.ts`). Ordine validazioni:
  1. ruolo: staff che marca se stesso → `STAFF_CANNOT_SELF_MARK`; User su altro → `NOT_STAFF`; Trainer su corso con `trainerId` altrui → `NOT_COURSE_TRAINER`;
  2. self con `present:false` → `SELF_CANNOT_MARK_ABSENT`;
  3. target non in `users.courses` → `ATTENDANCE_NOT_ENROLLED` (anche per staff: prima iscrive con `force`);
  4. finestra: self fuori `[-15', +30']` → `ATTENDANCE_WINDOW_NOT_OPEN` / `ATTENDANCE_WINDOW_CLOSED`; staff prima di `-30'` → `WINDOW_NOT_OPEN`;
  5. self con doc esistente `source != self` → `ATTENDANCE_ALREADY_RECORDED_BY_STAFF`; self già presente → `noop` idempotente (`changed:false`, non `already-exists`: doppio tap in sala non deve dare errore);
  6. `presentDelta = (requested?1:0) - (existing.present?1:0)`.
- **Handler** `setAttendanceHandler(request, db, nowMillis = Date.now())`: payload `{ courseId, userId?, present: boolean }` (`userId` assente = self). Transazione: letture (corso via `getCourseDoc`, attore, target, doc attendance) → `decideAttendance` → scritture (`tx.set(attRef, …, {merge:true})` con `markedAt` solo su create; `tx.update(course.ref, { attendance: {...} })` con `presentCount = max(0, prev + delta)`). Errori: `new HttpsError(code, msg, { reason })` — `details.reason` permette al client di distinguere i casi senza parsare stringhe. Risultato `{ ok, present, source, changed, presentCount }`.
- Esportare `asObject` e `requireString` da `enrollment.ts:65,72` invece di duplicarli una terza volta.

### `deleteCourseHandler` (`functions/src/enrollment/admin.ts:98-259`)

Leggere `attendance where courseId ==` in transazione, sommare al gate `MAX_AFFECTED_USERS`, cancellare i doc prima di `tx.delete(course.ref)`, aggiungere `removedAttendance` al risultato.

### `functions/src/index.ts`

Wrapper `setAttendance` dopo `recountCourseSubscribed` (:449): `region europe-west8`, `cors: true`, `stagingCloneGuarded` (necessario: senza guard un socio clonato scriverebbe presenze sul clone staging). Aggiungere a `indexExports.test.ts` e alla lista dello smoke-test in `.github/workflows/staging.yml:264-272`.

### `firestore.rules`

- Nuovo blocco dopo `subscriptions` (:184): `match /attendance/{id}`: `allow read: if isSignedIn() && (resource.data.userId == request.auth.uid || isAdmin() || isTrainer())`; `create, update, delete: false`. `allow read` copre get e list; `where userId == me` è dimostrabile per il socio, `where courseId ==` solo per lo staff (stesso pattern di `subscriptions`).
- Corsi: create (:148) aggiungere `!request.resource.data.keys().hasAny(['attendance'])`; update Admin (:160) e Trainer (:168) aggiungere `'attendance'` alla lista `affected().hasAny`.
- Non toccare `isSignedIn()`: `scripts/generate_staging_clone_rules.py` sostituisce quella stringa esatta e deve trovarla una sola volta.
- Sicuro per i client attuali: `update_course.dart:18-21` usa `update()` con `toJson` senza `attendance` → la chiave non entra in `affected()`.

### Test server

- `fakeDb.ts` (`functions/src/__tests__/helpers/`): aggiungere store `attendance`, `tx.set` con merge, `tx.get` su doc attendance e su query `where courseId`.
- `attendance.test.ts`: tabella `decideAttendance` (bordi finestra inclusivi, tutte le reason, tabella delta incluse transizioni self→staff); handler (doc scritto, marcatore, idempotenza self con store deep-equal, trainer sovrascrive self, clamp a 0, `details.reason`).
- `adminHandlers.test.ts`: deleteCourse cancella solo i doc del corso, `removedAttendance`, gate al limite.
- Integrazione `enrollment.integration.test.ts`: self dentro/fuori finestra (si spostano le `startDate` con Admin SDK), bloccato da staff, non iscritto, trainer altrui/proprio, admin, transizioni `presentCount`, deleteCourse ripulisce, **due setAttendance concorrenti su due soci → presentCount 2**.
- `firestoreRules.integration.test.ts`: read self ok / altrui no / anon no; list `where userId == me` ok, `where courseId` no per socio e ok per staff; ogni write negata; update corso con `attendance` negata per Admin e Trainer; regressione: rinominare un corso che ha già il marcatore passa.

## Lato client (Flutter)

### Trappole trovate nel codice (guidano il design)

- `getCourseState` ritorna `CLOSED` appena `now > startDate`, prima del check `user.courses.contains`: nella seconda metà della finestra self la card non ha nessun bottone. Lo stato del check-in **non** deriva da `CourseState` ma da `isSubscribed = currentUser.courses.contains(course.uid)`, calcolato in `CoursePreviewCard` (che ha `currentUser`; `CourseCard` non conosce l'uid).
- `CourseCard.isAdmin` è true sia per Admin che per Trainer e la card non sa se il Trainer è titolare: il check va in `CoursePreviewCard` e arriva come `bool canMarkAttendance`.
- Iscritti e waitlist si caricano in `initState` di `CoursePreviewCard`, non all'espansione: serve una callback `onSubscribersExpanded` da `CourseCard` per caricare i doc attendance solo quando servono.
- Nessuna card si ricostruisce allo scadere di una finestra: serve un `Timer` one-shot "al prossimo confine" in `CoursePreviewCard` (`nextAttendanceBoundary`).
- `callEnrollmentFunction` dispatcha il Loader globale full-screen a ogni chiamata: inaccettabile per 15 tocchi a lezione → nuovo parametro `showGlobalLoader` (la guardia simulazione resta prima e incondizionata).
- `EnrollmentException` scarta `e.details`: estenderla con `details` e leggere `details['reason']`, con fallback regex `ATTENDANCE_[A-Z_]+` sul messaggio.
- `Course.toJson` alimenta `set`/`update` client: **non** emettere `attendance`; in più `..remove('attendance')` difensivo in `update_course.dart:18-20`.

### Modello

- `lib/types/attendance_record.dart` (nuovo): `AttendanceSource {self, trainer, admin}`, `AttendanceRecord` (fromJson/toJson manuali, `docId(courseId, userId)`, `isStaffRecorded`, `copyWith`), `CourseAttendanceSummary {lastMarkedAt, lastMarkedBy, presentCount}`.
- `lib/types/course.dart`: campo `CourseAttendanceSummary? attendance`, letto in `fromJson`, preservato da `copyWith`, **mai emesso** da `toJson` (commento esplicito). Test: serializzazione + estensione di `test/update_course_test.dart` (la mappa in DB resta intatta dopo `updateCourse`).

### API (`lib/api/courses/`)

- `enrollment_callable.dart`: `bool showGlobalLoader = true`; `EnrollmentException.details`; aggiornare commento "choke point" (7 callable) e `simulation_layer_a_test.dart`.
- `set_attendance.dart` (nuovo): `setAttendance({courseId, userId?, present, showGlobalLoader})` via `callEnrollmentFunction('setAttendance', …, userId: null)` + `whenComplete(invalidateAttendanceCache)`; `AttendanceRejectReason` + `attendanceErrorMessage(error)` con testi italiani (finestra chiusa → "chiedi al trainer", non aperta, già registrata dallo staff, non titolare).
- `get_attendance.dart` (nuovo): `getCourseAttendance(courseId)` (`where courseId ==`, staff) e `getMyAttendance(courseId, uid)` (get su id deterministico, cache anche del `null`); cache TTL 1 min nella forma di `get_courses.dart:4-7`; `invalidateAttendanceCache()`. Strategia socio: get per-card **solo se** `isSubscribed && now >= start − 15'` → zero letture sul calendario futuro, nessun indice composito.
- Test con `FakeFirebaseFirestore` (pattern `test/manage_subscription_api_test.dart`).

### Logica pura `lib/utils/attendance_window.dart` (nuovo, con `now` esplicito)

`SelfCheckInState {notYetOpen, open, closedAskTrainer, presentSelf, presentStaff, absentStaff}`; `selfCheckInState(course, record, now, {isSubscribed})` (null se non iscritto; il record vince sul tempo; finestra inclusiva `[−15', +30']`); `staffCanMark(course, now)` (`≥ start − 30'`); `nextAttendanceBoundary(course, now)`; `isMarkedPresent(record)`. Test sui confini esatti e sulla precedenza record > tempo.

### Widget

- `lib/components/self_checkin_button.dart` (nuovo): un widget per tutti gli stati socio. `open` → `ElevatedButton` "Sono in sala" verde AA `0xFF2E7D32`, lock `_isProcessing` come `renderButtonSubscribe`; `presentSelf` → pill "Presente"; `presentStaff` → pill "Presenza registrata"; `closedAskTrainer` → **avviso inline** ambra "Check-in chiuso: chiedi al trainer di registrare la tua presenza" (non un dialog: scatterebbe a ogni rebuild); `absentStaff` → avviso rosso tenue "Risulti assente. Se eri in sala, chiedi al trainer di correggere"; `notYetOpen` → niente (evita altezza extra su tutte le card future, lezione layout-shift).
- `lib/components/attendance_toggle.dart` (nuovo): `FilterChip` "Presente" (area tocco 48 px, meglio di Checkbox/Switch in palestra), `selected = isMarkedPresent`, `pending` → spinner inline e tap disabilitato, sotto-etichetta "dichiarata dal socio" se `source == self`.
- `course_card.dart`: nuove prop `selfCheckInState`, `onSelfCheckIn`, `canMarkAttendance`, `showPresentCount`, `attendanceRecords`, `pendingAttendanceUids`, `onToggleAttendance`, `onSubscribersExpanded`. Pill "Presenti N" nell'intestazione (`:373-402`): N = conteggio locale se i record sono caricati, altrimenti `course.attendance.presentCount`. Chip per riga iscritto (`:443-481`), nome con `overflow: ellipsis`; chip `pending` durante il caricamento (nessun salto di altezza). Riga azioni socio (`:893-897`) da `Row` a `Wrap` (in `[−15', 0]` coesiste con "Rimuovi iscrizione"); avvisi full-width sotto. Resta presentazionale, nessuna rete.
- `course_preview_card.dart`: stato `_attendance`, `_myAttendanceFuture`, `_pendingAttendanceUids`, `_boundaryTimer`; `isOwnerStaff = Admin || (Trainer && (trainerId == uid || trainerId vuoto))`; `canMarkAttendance = isStaff && isOwnerStaff && staffCanMark`; `showPresentCount = isStaff && staffCanMark` (il Trainer non titolare vede il conteggio, non i controlli). Toggle staff: spinner per riga, flip **alla risposta** (non ottimistico: niente revert sotto guardia simulazione o `permission-denied`); self check-in con Loader globale (tap singolo, coerente con "Prenotati").
- Pagine: `calendar_page.dart` `onSelfCheckIn` e `onToggleAttendance` (prima istruzione `SimulationGuard.blockIfSimulating(context)`, ritornano `bool`; errori via `SnackBarUtils` + `attendanceErrorMessage`); **nessun** `updateCourses()` dopo il toggle (collasserebbe la card). `home_page.dart`: solo `onSelfCheckIn`. `course_agenda_row.dart` fuori scope v1.

### Test widget

`self_checkin_button_test.dart` (tutti gli stati, lock asincrono), `attendance_toggle_test.dart` (selected, pending, etichetta self), aggiunte a `course_card_widget_test.dart`: "Sono in sala" con `courseState: CLOSED` (regressione trappola 1); Wrap con "Rimuovi iscrizione"; staff non titolare senza chip; "Presenti 3" a lista collassata; conteggio locale vince; `onSubscribersExpanded` solo all'apertura; chip pending disabilitato.

## Rollout

**functions → rules → web** (inverso della regola di casa, motivato): le rules aprono la lettura di una collezione nuova che la web deve leggere; la parte restrittiva non tocca alcun payload client attuale; la callable funziona senza rules (Admin SDK). Produzione: `firebase deploy --project prod --only functions`, poi `--only firestore:rules`, poi upload Hostinger. Su staging l'ordine dei job esistente resta accettabile.

## Documentazione da aggiornare

- `lib/api/courses/README_ISCRIZIONI.md`: riga `setAttendance` in tabella + reason `ATTENDANCE_*` e `details.reason` nella sezione sicurezza + nota indice composito futuro.
- `agents.md`: collezione `attendance` (:466), campo server-owned su courses (:473), riga in Restrizioni ruolo (:423-427).
- `CLAUDE.md:185`: aggiungere "presenze" all'elenco delle callable; una riga su finestre e rollout.
- Commento di testa `firestore.rules`.

## Sequenza di implementazione (PR unica su `develop`, TDD)

0. Salvare questo design come spec in `docs/superpowers/specs/2026-09-30-presenze-corsi-design.md` e committarlo.
1. Server: `export` di `asObject`/`requireString` → `attendance.ts` (`decideAttendance` + test puri) → `fakeDb.ts` + handler + test → `deleteCourse` → `index.ts` + `indexExports.test.ts` + `staging.yml` → rules + test rules → test integrazione → doc.
2. Client: modello + test → `attendance_window.dart` + test → `enrollment_callable.dart` + `set_attendance.dart` + `get_attendance.dart` + test → widget foglia + test → `course_card.dart` + test → `course_preview_card.dart` → pagine → doc.
3. Gate: `flutter test`, `flutter analyze --no-fatal-infos`, `dart format --set-exit-if-changed .`; in `functions/`: `npm run build && npm test && npm run test:integration`. Prima della PR: `grep -rn "assertNotSimulating" lib/api lib/services lib/authentication`.
4. PR: `gh pr create --repo fgrotta/fitrope_app --base develop`.

## Verifica

1. `cd functions && npm run build && npm test && npm run test:integration` (emulatore su porte alternative se un altro worktree lo occupa).
2. `flutter test && flutter analyze --no-fatal-infos && dart format --set-exit-if-changed .` (dopo `flutter pub get`).
3. QA sull'emulatore (`./scripts/dev_emulator.sh`), con corsi seedati alla settimana prossima: spostare `startDate` via REST per entrare nelle finestre. Scenari: socio dentro finestra → "Presente"; a +31' → avviso "chiedi al trainer"; trainer titolare spunta/despunta e vede "Presenti N"; trainer non titolare non vede i controlli; Admin in simulazione: bottoni visibili ma bloccati da `SimulationGuard`; conferma su Firestore via REST (`attendance/*` e `courses.attendance`).
