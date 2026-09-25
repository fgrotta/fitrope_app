# WhatsApp lezioni demo su `develop` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Riportare su `develop` l'integrazione WhatsApp → webhook Make per le lezioni di prova (conferma all'iscrizione + promemoria la sera prima), adattandola all'architettura attuale: iscrizione server-side, modello multi-abbonamento, ambiente di staging e deploy automatico.

**Architecture:** La conferma diventa una notifica best-effort in più dentro `subscribeToCourseHandler` (`EnrollmentDeps.notifyTrialWhatsapp`), accanto alle email già esistenti. Il cron seleziona gli utenti iscritti ai corsi di domani con `array-contains-any` e li filtra con lo stesso predicato "utente di prova" dell'iscrizione, estratto in un modulo condiviso. Tutto il codice WhatsApp vive in `functions/src/whatsapp/` in moduli piccoli a responsabilità singola; cosa esiste in un progetto lo decide `WHATSAPP_DEMO_MODE` (`off`/`test`/`live`), letta in fase di discovery come i gate dei certificati.

**Tech Stack:** Cloud Functions v2 TypeScript (firebase-functions 7.3.2, firebase-admin 12.7.0, Node ≥22 <25), Jest + ts-jest, Flutter/Dart (solo pagina di debug).

**Spec:** non esiste un documento di spec separato. La fonte è:
- il piano originale approvato il 2026-09-03: `~/.claude/plans/system-instruction-you-are-working-lively-sloth.md`;
- l'implementazione di riferimento sul branch `fgrotta/make-whatsapp-webhook-demo` (commit `b686af2`, file `functions/src/makeWebhook.ts` e `functions/src/__tests__/makeWebhook.test.ts`), nato da `main` v1.2.7 e **mai integrato**;
- la sezione "Decisioni" qui sotto, che registra cosa cambia rispetto al riferimento e perché.

## Global Constraints

- PR **solo** verso `develop` del fork: `gh pr create --repo fgrotta/fitrope_app --base develop`. Mai base `main`, mai verso l'upstream `dellarosamarco/fitrope_app`.
- Node `>=22 <25`, `firebase-functions` 7.3.2, `firebase-admin` 12.7.0: nessuna nuova dipendenza npm.
- Import modulari per i valori runtime: `import { Timestamp } from "firebase-admin/firestore"`. Vietato `admin.firestore.Timestamp` / `admin.firestore.FieldValue` in `src/` (lo blocca `conventions.test.ts`).
- Region `europe-west8` per callable **e** schedulate, come il resto di `develop`.
- Contratto del body verso Make: **esattamente** le chiavi `tipo, nome, numero_di_telefono, corso, giorno, orario`, tutte stringhe non vuote. `tipo` ∈ {`conferma`, `promemoria`}; `giorno` nel formato `15 ottobre 2026` (mese minuscolo, con anno, senza giorno della settimana); `orario` nel formato `18:00` (solo inizio).
- Chiave di autenticazione nell'header HTTP `Demo-Reminder`, mai nel body. Secret: `MAKE_WEBHOOK_URL`, `MAKE_WEBHOOK_KEY`. URL e chiave non compaiono mai in alcun log.
- Cron: `schedule: "0 19 * * *"`, `timeZone: "Europe/Rome"`.
- Invii incerti (timeout, errore di rete, HTTP 5xx, interruzione dopo il claim): **nessun reinvio automatico**. Il registro li segnala per verifica in Make; la priorità è evitare WhatsApp duplicati e addebiti doppi. Solo HTTP 429 viene ritentato, al massimo due volte nello stesso run.
- "Utente di prova" = predicato di `develop`: abbonamento vivo con `planKey === "open_trial_1i_30d"`, oppure (legacy) nessun abbonamento vivo + `subscriptionModelVersion < 2` + `tipologiaIscrizione === "ABBONAMENTO_PROVA"`.
- Nessun nuovo flag di consenso sull'utente: si invia a chi ha un `numeroTelefono` mobile valido ed è `isActive !== false`.
- OneSignal (email e push della prova) **non si tocca**.
- UI in italiano. Il codice Dart deve passare `dart format --set-exit-if-changed .` (lancia prima `flutter pub get`, altrimenti `dart format` usa lo stile sbagliato).
- Termina ogni messaggio di commit e la descrizione della PR con le righe di attribuzione richieste dall'ambiente di esecuzione.
- **Mai `git add -A` o `git add .`**: nel worktree può esserci un `functions/.env.fit-rope-staging` untracked e non ignorato. Aggiungi sempre i file per nome.

## Review Focus

1. **Cliente pagante con tipologia legacy PROVA iscritto a una lezione di domani.** Chi è stato convertito al multi-abbonamento può avere ancora `tipologiaIscrizione: "ABBONAMENTO_PROVA"`: non deve ricevere il WhatsApp "demo". Test → Task 8, "non scrive al cliente convertito che ha ancora la tipologia PROVA".
2. **Staging con dati clonati da produzione e modalità accesa per errore.** Su staging i numeri possono essere reali: senza allowlist non parte nulla. Test → Task 4 (`isWhatsappRecipientAllowed`) e Task 7, "su staging scarta i numeri fuori allowlist".
3. **`activeSubscriptions` malformato su un utente.** `snapshotRecords` lancia un'eccezione: il cron deve contare l'errore e continuare con gli altri utenti. Test → Task 8, "uno snapshot illeggibile non ferma il run".
4. **Più di 30 corsi domani.** `array-contains-any` accetta massimo 30 valori: servono più query, e un utente iscritto a corsi in due blocchi diversi va letto una volta sola, con un messaggio per ciascun corso. Test → Task 8, "spezza le query oltre i 30 corsi e non duplica gli utenti".
5. **Chiunque sia autenticato che chiama la callable di prova.** In produzione oggi basta essere loggati per mandare WhatsApp a numeri arbitrari. Nel porting deve servire il ruolo Admin. Test → Task 9, "nega a %s: servono i permessi Admin" (trainer, member e utente senza documento).
6. **Configurazione produzione ignorata da Git.** `origin/develop` ignora `/functions/.env.*`: il Task 11 deve aggiungere una sola eccezione per `.env.fit-rope-app-1f575` e il Task 14 deve verificarne la presenza nel commit.
7. **Cron interrotto o POST con esito incerto.** I tentativi del job devono riprendere i candidati non elaborati usando `event.scheduleTime`; i claim incerti restano bloccati e visibili per la verifica manuale. Test → Task 6–8.

## Decisioni e differenze rispetto al branch di riferimento

| # | Decisione | Perché |
|---|---|---|
| 1 | La conferma parte da `subscribeToCourseHandler` tramite `EnrollmentDeps.notifyTrialWhatsapp`. Spariscono la callable `notifyDemoLessonBooked`, il wrapper Dart e `is_demo_lesson_user.dart` | Su `develop` l'iscrizione è server-side (`lib/api/courses/subscribeToCourse.dart` non esiste più). Il server sa già se l'utente è di prova, il client non può saltare l'invio e non serve più controllare chi può notificare chi |
| 2 | Predicato di prova estratto in `functions/src/enrollment/trial.ts`, usato dall'iscrizione e dal cron | La query del riferimento (`tipologiaIscrizione == PROVA`) scriverebbe ai clienti convertiti e non vedrebbe le prove del nuovo modello |
| 3 | Il cron legge i corsi di domani e poi `users.where("courses", "array-contains-any", ids)` a blocchi da 30, quindi filtra con il predicato in memoria | Nel nuovo modello non si può filtrare su `planKey` dentro un array di mappe. Con un solo filtro non serve un indice composito, e le letture scalano con gli iscritti di domani, non con tutti gli utenti di prova |
| 4 | Nessun `romeTime.ts` e nessun refactor di `certificateEmails.ts`: si riusano `romeParts` e `romeWallClockToUtcMillis` di `enrollment/notify.ts` | `develop` ha già tre implementazioni dell'offset di Roma; una quarta sarebbe solo debito. La conversione a passo singolo è esatta a mezzanotte (in Europa l'ora cambia alle 01:00 UTC), quindi la finestra "domani" non ha bisogno di padding |
| 5 | `WHATSAPP_DEMO_MODE` = `off` (default) / `test` / `live`, letta in discovery. I secret Make vengono dichiarati solo se la modalità non è `off` | Mergiare significa deployare: il cron resta spento grazie al gate, non per scelta manuale. Su staging (modalità `off`) il deploy non chiede secret che lì non esistono |
| 6 | Su staging (`APP_ENV=staging`) ogni invio richiede il numero in `STAGING_WHATSAPP_ALLOWLIST` | Staging può contenere un clone dei dati di produzione con numeri reali (`STAGING_CLONE_MODE`) |
| 7 | La callable di prova richiede il ruolo **Admin** | Quella deployata oggi richiede solo il login: chiunque sia registrato potrebbe mandare WhatsApp a pagamento a numeri arbitrari |
| 8 | Produzione in modalità `test` tramite `functions/.env.fit-rope-app-1f575` | Così `sendTestDemoLessonWebhook`, già in produzione, resta nel codice (update e non delete), e da produzione si può verificare lo scenario Make prima di passare a `live` |
| 9 | `notifyDemoLessonBooked` non esiste più nel codice. Cancellarla dalla produzione è uno **step di rilascio** e questo piano non lo esegue | L'utente ha chiesto di lasciarla in produzione per ora. Finché resta lì, il deploy non interattivo di produzione si ferma su di lei (vedi "Rilascio") |
| 10 | Claim persistente con esiti `pending`/`sent`/`rejected`/`unknown`; solo `sent` sopprime un promemoria. HTTP 429 ha due nuovi tentativi limitati; timeout, rete e 5xx richiedono verifica manuale | Make può accettare un messaggio anche se la risposta non arriva alla function: ritentare un esito incerto può generare due WhatsApp a pagamento |
| 11 | Cron con massimo 10 invii concorrenti, deadline interna a 480 s, timeout a 540 s e massimo tre tentativi del job ancorati a `event.scheduleTime` | Un batch lento non deve perdere i destinatari non ancora elaborati; il registro impedisce di rimandare quelli già confermati |

## Struttura dei file

**Da creare**

| File | Responsabilità |
|---|---|
| `functions/src/enrollment/trial.ts` | `TRIAL_PLAN_KEY`, `isTrialUser(user, liveRecords)`, puro |
| `functions/src/whatsapp/phone.ts` | `normalizePhoneE164`, puro |
| `functions/src/whatsapp/format.ts` | `formatGiorno`, `formatOrario`, `isSameRomeDay`, `tomorrowRomeRange`, puro (su `notify.ts`) |
| `functions/src/whatsapp/payload.ts` | tipi del body, `sanitizeTemplateParam`, `buildNome`, `buildDemoLessonPayload`, puro |
| `functions/src/whatsapp/environment.ts` | `whatsappDemoMode(env)`, `isWhatsappRecipientAllowed(e164, env)`, puro |
| `functions/src/whatsapp/makeClient.ts` | `postToMake`: unica chiamata HTTP verso Make |
| `functions/src/whatsapp/sendLog.ts` | registro invii `demoLessonWebhookLog`: claim, esito e `wasNotifiedToday` |
| `functions/src/whatsapp/demoLesson.ts` | tipi di dominio, `checkRecipient`, `dispatchDemoLesson`, `notifyDemoLessonBooked` |
| `functions/src/whatsapp/reminders.ts` | `runDemoLessonReminders` (cron) |
| `functions/src/whatsapp/testWebhook.ts` | `sendTestDemoLessonWebhookHandler` (callable di prova, solo Admin) |
| `functions/.env.fit-rope-app-1f575` | `WHATSAPP_DEMO_MODE=test` per la produzione |
| `functions/src/__tests__/helpers/whatsappFakeDb.ts` | Firestore in memoria per i test WhatsApp |
| `functions/src/__tests__/trial.test.ts`, `whatsappPhone.test.ts`, `whatsappFormat.test.ts`, `whatsappPayload.test.ts`, `whatsappEnvironment.test.ts`, `whatsappMakeClient.test.ts`, `whatsappSendLog.test.ts`, `whatsappDemoLesson.test.ts`, `whatsappReminders.test.ts`, `whatsappTestWebhook.test.ts` | un file di test per modulo |

**Da modificare**

- `functions/src/enrollment/enrollment.ts`: usa `isTrialUser` di `trial.ts` e aggiunge `notifyTrialWhatsapp` a `EnrollmentDeps` e al blocco `if (isTrialUser)`.
- `functions/src/index.ts`: gate `WHATSAPP_DEMO_MODE`, secret condizionali, dipendenza WhatsApp in `subscribeToCourse`, due export condizionali.
- `.gitignore`: eccezione esplicita per la sola configurazione Functions di produzione.
- `functions/src/__tests__/enrollmentHandlers.test.ts`: test della nuova dipendenza.
- `functions/src/__tests__/indexExports.test.ts`: test del gate.
- `lib/services/notification_service.dart` e `lib/pages/protected/debug_email_page.dart`: sezione WhatsApp nella pagina di debug.
- `CLAUDE.md`, `agents.md`, `lib/api/courses/README_ISCRIZIONI.md`, `functions/.env.staging.example`: documentazione.

---

### Task 0: Branch da `develop` e baseline verde

**Files:**
- Create: nessuno (il piano arriva già untracked in `docs/superpowers/plans/`)

**Interfaces:**
- Consumes: niente
- Produces: branch `fgrotta/whatsapp-demo-develop` allineato a `origin/develop`, con le suite verdi prima di qualsiasi modifica

- [ ] **Step 1: Crea il branch da `origin/develop`**

Se esegui in un worktree nuovo e non in quello dove è stato scritto il piano, copia prima il file da `/Users/Frank/conductor/workspaces/fitrope_app-v1/nagoya/docs/superpowers/plans/2026-09-25-whatsapp-demo-su-develop.md` nello stesso percorso del nuovo worktree.

```bash
git fetch origin
git switch -c fgrotta/whatsapp-demo-develop origin/develop
git status --short
```

Expected: tra gli untracked compare `docs/superpowers/plans/2026-09-25-whatsapp-demo-su-develop.md`, ed eventualmente `functions/.env.fit-rope-staging`. **Non aggiungere** quest'ultimo, né ora né più avanti.

- [ ] **Step 2: Installa le dipendenze e verifica la baseline delle functions**

```bash
cd functions && npm ci && npm run build && npm test
```

Expected: tutte le suite PASS. Se `tsc: command not found`, manca `npm ci`: non è un problema di PATH.

- [ ] **Step 3: Verifica la baseline Flutter**

```bash
cd .. && flutter pub get && flutter test && flutter analyze --no-fatal-infos
```

Expected: tutti i test PASS, nessun errore di analyze.

- [ ] **Step 4: Committa il piano**

```bash
git add docs/superpowers/plans/2026-09-25-whatsapp-demo-su-develop.md
git commit -m "docs: piano di implementazione WhatsApp demo su develop"
```

---

### Task 1: Predicato "utente di prova" condiviso

Area sensibile: prima di iniziare leggi `lib/api/courses/README_ISCRIZIONI.md`. A fine task chiedi una revisione all'agente `fitrope-enrollment-reviewer`.

**Files:**
- Create: `functions/src/enrollment/trial.ts`
- Modify: `functions/src/enrollment/enrollment.ts` (import in testa; calcolo di `isTrialUser`, oggi alle righe 499-508)
- Test: `functions/src/__tests__/trial.test.ts`

**Interfaces:**
- Consumes: `UserSubscriptionRecord` da `functions/src/enrollment/subscription.ts`; `planByKey` da `functions/src/enrollment/plansCatalog.ts`
- Produces: `export const TRIAL_PLAN_KEY = "open_trial_1i_30d"`; `export function isTrialUser(user: DocumentData, liveRecords: UserSubscriptionRecord[]): boolean`

- [ ] **Step 1: Scrivi il test che fallisce**

`functions/src/__tests__/trial.test.ts`:

```ts
import { isTrialUser, TRIAL_PLAN_KEY } from "../enrollment/trial";
import { planByKey } from "../enrollment/plansCatalog";
import { UserSubscriptionRecord } from "../enrollment/subscription";

function record(planKey: string): UserSubscriptionRecord {
  return {
    id: planKey,
    planKey,
    family: "OPEN",
    billingMode: "ENTRIES",
    courseTypeTags: ["Open"],
    weeklyFrequency: null,
    remainingEntries: 1,
    startDateMillis: 0,
    endDateMillis: Number.MAX_SAFE_INTEGER,
  };
}

describe("isTrialUser", () => {
  test("TRIAL_PLAN_KEY esiste nel catalogo piani (guardia contro il drift)", () => {
    expect(planByKey(TRIAL_PLAN_KEY)).toBeDefined();
  });

  test("modello V2: abbonamento vivo sul piano di prova", () => {
    expect(isTrialUser({ subscriptionModelVersion: 2 }, [record(TRIAL_PLAN_KEY)])).toBe(true);
  });

  test("convertito al multi-abbonamento con tipologia legacy PROVA: NON è di prova", () => {
    expect(
      isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA" }, [record("open_2x_3m")])
    ).toBe(false);
  });

  test("legacy PROVA senza abbonamenti vivi e senza versione: è di prova", () => {
    expect(isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA" }, [])).toBe(true);
  });

  test("legacy PROVA ma già sul modello V2: NON è di prova", () => {
    expect(
      isTrialUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA", subscriptionModelVersion: 2 }, [])
    ).toBe(false);
  });

  test("legacy non PROVA: NON è di prova", () => {
    expect(isTrialUser({ tipologiaIscrizione: "PACCHETTO_ENTRATE" }, [])).toBe(false);
  });
});
```

- [ ] **Step 2: Verifica che fallisca**

Run: `cd functions && npx jest src/__tests__/trial.test.ts`
Expected: FAIL con `Cannot find module '../enrollment/trial'`

- [ ] **Step 3: Implementa `trial.ts`**

`functions/src/enrollment/trial.ts`:

```ts
// Predicato "utente di prova", condiviso tra iscrizione (subscribeToCourseHandler)
// e promemoria WhatsApp (whatsapp/reminders.ts).
//
// Estratto da subscribeToCourseHandler senza cambiarne il comportamento: un
// utente è di prova se ha un abbonamento vivo sul piano di prova, oppure se è
// ancora sul modello legacy (nessun abbonamento vivo, subscriptionModelVersion
// < 2) con tipologia ABBONAMENTO_PROVA. Uno snapshot vivo di altro tipo
// significa che l'utente è stato convertito al multi-abbonamento, anche se la
// tipologia legacy è rimasta PROVA: in quel caso NON è di prova.

import type { DocumentData } from "firebase-admin/firestore";
import { UserSubscriptionRecord } from "./subscription";

/** Chiave del piano "Prova Open · 1 ingresso · 30 giorni" (plansCatalog.ts). */
export const TRIAL_PLAN_KEY = "open_trial_1i_30d";

export function isTrialUser(
  user: DocumentData,
  liveRecords: UserSubscriptionRecord[]
): boolean {
  if (liveRecords.some((record) => record.planKey === TRIAL_PLAN_KEY)) {
    return true;
  }
  return (
    liveRecords.length === 0 &&
    ((user.subscriptionModelVersion as number | null) ?? 1) < 2 &&
    user.tipologiaIscrizione === "ABBONAMENTO_PROVA"
  );
}
```

- [ ] **Step 4: Verifica che passi**

Run: `cd functions && npx jest src/__tests__/trial.test.ts`
Expected: PASS (6 test)

- [ ] **Step 5: Usa il predicato in `enrollment.ts`**

In `functions/src/enrollment/enrollment.ts` aggiungi l'import sotto quello di `./courseTypes`:

```ts
import { typeTagOf } from "./courseTypes";
import { isTrialUser as computeIsTrialUser } from "./trial";
```

L'alias serve perché dentro `subscribeToCourseHandler` esiste già una variabile locale `let isTrialUser`. Poi sostituisci il blocco (oggi alle righe 502-508):

```ts
    isTrialUser = liveRecords.some(
      (record) => record.planKey === "open_trial_1i_30d"
    ) || (
      liveRecords.length === 0 &&
      ((user.subscriptionModelVersion as number | null) ?? 1) < 2 &&
      user.tipologiaIscrizione === "ABBONAMENTO_PROVA"
    );
```

con:

```ts
    isTrialUser = computeIsTrialUser(user, liveRecords);
```

Lascia com'è il commento subito sopra ("Promemoria prova: solo per utenti ancora sul modello legacy…").

- [ ] **Step 6: Verifica che l'iscrizione non cambi comportamento**

Run: `cd functions && npx jest src/__tests__/trial.test.ts src/__tests__/enrollmentHandlers.test.ts src/__tests__/conventions.test.ts`
Expected: PASS. In particolare restano verdi, **senza modifiche**, "piano Prova V2 conserva conferma e promemoria", "utente non PROVA: nessun promemoria" e "PROVA convertito al multi-abbonamento: NESSUN promemoria prova".

- [ ] **Step 7: Commit**

```bash
git add functions/src/enrollment/trial.ts functions/src/enrollment/enrollment.ts functions/src/__tests__/trial.test.ts
git commit -m "refactor(enrollment): estrai il predicato utente di prova in trial.ts"
```

---

### Task 2: Normalizzazione del numero di telefono

**Files:**
- Create: `functions/src/whatsapp/phone.ts`
- Test: `functions/src/__tests__/whatsappPhone.test.ts`

**Interfaces:**
- Consumes: niente
- Produces: `export interface NormalizedPhone { e164: string | null; digits: string | null; likelyMobile: boolean; reason?: "empty" | "placeholder" | "not_numeric" | "too_short" | "too_long" }`; `export function normalizePhoneE164(raw: string | null | undefined): NormalizedPhone`

- [ ] **Step 1: Scrivi il test che fallisce**

`functions/src/__tests__/whatsappPhone.test.ts`:

```ts
import { normalizePhoneE164 } from "../whatsapp/phone";

describe("normalizePhoneE164", () => {
  test.each([
    ["null", null],
    ["undefined", undefined],
    ["stringa vuota", ""],
    ["soli spazi", "   "],
  ])("scarta %s con reason empty", (_label, input) => {
    expect(normalizePhoneE164(input)).toMatchObject({ e164: null, reason: "empty" });
  });

  test("riconosce il placeholder '-'", () => {
    expect(normalizePhoneE164("-")).toMatchObject({ e164: null, reason: "placeholder" });
  });

  test("scarta il testo non numerico", () => {
    expect(normalizePhoneE164("n/d")).toMatchObject({ e164: null, reason: "not_numeric" });
  });

  test.each([
    ["spazi", "333 123 4567"],
    ["trattini e punti", "333-123.4567"],
    ["parentesi", "(333) 1234567"],
    ["NBSP", "333 1234567"],
  ])("rimuove i separatori (%s)", (_label, input) => {
    expect(normalizePhoneE164(input)).toEqual({
      e164: "+393331234567",
      digits: "393331234567",
      likelyMobile: true,
    });
  });

  test("accetta un cellulare a 9 cifre", () => {
    expect(normalizePhoneE164("335123456")).toMatchObject({
      e164: "+39335123456",
      likelyMobile: true,
    });
  });

  test("lascia invariato un numero già internazionale", () => {
    expect(normalizePhoneE164("+393331234567")).toMatchObject({
      e164: "+393331234567",
      likelyMobile: true,
    });
  });

  test("converte il prefisso 00 in +", () => {
    expect(normalizePhoneE164("00393331234567")).toMatchObject({ e164: "+393331234567" });
  });

  test("NON tratta un 39 iniziale su 10 cifre come prefisso paese", () => {
    expect(normalizePhoneE164("3931234567")).toMatchObject({
      e164: "+393931234567",
      likelyMobile: true,
    });
  });

  test("preserva un numero estero senza forzare il +39", () => {
    expect(normalizePhoneE164("+41791234567")).toMatchObject({
      e164: "+41791234567",
      likelyMobile: true,
    });
  });

  test("marca un fisso come non mobile", () => {
    expect(normalizePhoneE164("0392123456")).toMatchObject({
      e164: "+390392123456",
      likelyMobile: false,
    });
  });

  test("scarta due numeri nello stesso campo", () => {
    expect(normalizePhoneE164("3331234567 / 3339876543")).toMatchObject({
      e164: null,
      reason: "too_long",
    });
  });

  test("scarta un numero troppo corto", () => {
    expect(normalizePhoneE164("+39")).toMatchObject({ e164: null, reason: "too_short" });
    expect(normalizePhoneE164("12345")).toMatchObject({ e164: null, reason: "too_short" });
  });
});
```

- [ ] **Step 2: Verifica che fallisca**

Run: `cd functions && npx jest src/__tests__/whatsappPhone.test.ts`
Expected: FAIL con `Cannot find module '../whatsapp/phone'`

- [ ] **Step 3: Implementa `phone.ts`**

`functions/src/whatsapp/phone.ts`:

```ts
// Normalizzazione di `users/{uid}.numeroTelefono` verso E.164 per il webhook Make.
//
// Il dato di norma è pulito (le schermate validano 10 cifre, provisioning.ts fa
// solo trim()), ma record creati da console, import o versioni precedenti
// possono contenere separatori, prefissi internazionali, fissi o due numeri.

export interface NormalizedPhone {
  /** Numero in formato E.164 (con il `+`), o `null` se non utilizzabile. */
  e164: string | null;
  /** Sole cifre, senza `+`. */
  digits: string | null;
  /** `false` se il numero non è (probabilmente) raggiungibile su WhatsApp. */
  likelyMobile: boolean;
  /** Motivo dello scarto, per i log. */
  reason?: "empty" | "placeholder" | "not_numeric" | "too_short" | "too_long";
}

const E164_MIN = 8;
const E164_MAX = 15;
const IT_NATIONAL_MIN = 6;
const IT_NATIONAL_MAX = 11;

export function normalizePhoneE164(raw: string | null | undefined): NormalizedPhone {
  const nope = (reason: NonNullable<NormalizedPhone["reason"]>): NormalizedPhone => ({
    e164: null,
    digits: null,
    likelyMobile: false,
    reason,
  });

  if (raw === null || raw === undefined) return nope("empty");
  // \s non copre l'NBSP in tutte le versioni di JS: lo normalizzo a mano.
  const trimmed = raw.replace(/ /g, " ").trim();
  if (trimmed === "") return nope("empty");
  // '-' è il placeholder usato nei campi anagrafici mancanti.
  if (trimmed === "-") return nope("placeholder");

  const hasPlus = trimmed.startsWith("+");
  let digits = trimmed.replace(/\D/g, "");
  if (digits === "") return nope("not_numeric");

  // Prefisso internazionale scritto come 00 anziché +.
  let international = hasPlus;
  if (!international && digits.startsWith("00") && digits.length >= 12) {
    digits = digits.slice(2);
    international = true;
  }

  if (international) {
    if (digits.length < E164_MIN) return nope("too_short");
    if (digits.length > E164_MAX) return nope("too_long");
    const national = digits.startsWith("39") ? digits.slice(2) : null;
    return {
      e164: `+${digits}`,
      digits,
      // Fuori dall'Italia il prefisso non dice se è un cellulare: meglio provare
      // che scartare in silenzio un destinatario valido.
      likelyMobile: national === null ? true : isItalianMobile(national),
    };
  }

  // Un `39` iniziale su 10 cifre NON è il prefisso paese ma l'inizio del numero
  // (es. 3931234567): lo tolgo solo da 12 cifre in su.
  const national =
    digits.startsWith("39") && digits.length >= 12 ? digits.slice(2) : digits;
  if (national.length < IT_NATIONAL_MIN) return nope("too_short");
  if (national.length > IT_NATIONAL_MAX) return nope("too_long");

  const full = `39${national}`;
  return { e164: `+${full}`, digits: full, likelyMobile: isItalianMobile(national) };
}

/** I cellulari italiani iniziano per 3 e hanno 9 o 10 cifre. */
function isItalianMobile(national: string): boolean {
  return national.startsWith("3") && national.length >= 9 && national.length <= 10;
}
```

- [ ] **Step 4: Verifica che passi**

Run: `cd functions && npx jest src/__tests__/whatsappPhone.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add functions/src/whatsapp/phone.ts functions/src/__tests__/whatsappPhone.test.ts
git commit -m "feat(whatsapp): normalizzazione E.164 del numero di telefono"
```

---

### Task 3: Formati data/ora e payload verso Make

**Files:**
- Create: `functions/src/whatsapp/format.ts`, `functions/src/whatsapp/payload.ts`
- Test: `functions/src/__tests__/whatsappFormat.test.ts`, `functions/src/__tests__/whatsappPayload.test.ts`

**Interfaces:**
- Consumes: `romeParts(millis: number): RomeParts` e `romeWallClockToUtcMillis(year, month, day, hour, minute): number` da `functions/src/enrollment/notify.ts`
- Produces:
  - `format.ts`: `export const MONTH_NAMES_IT: string[]`; `export function formatGiorno(millis: number): string`; `export function formatOrario(millis: number): string`; `export function isSameRomeDay(aMillis: number, bMillis: number): boolean`; `export interface RomeDayRange { startMs: number; endMs: number }`; `export function tomorrowRomeRange(nowMillis: number): RomeDayRange`
  - `payload.ts`: `export type DemoWebhookKind = "booked" | "reminder"`; `export const TIPO_BY_KIND: Record<DemoWebhookKind, string>`; `export interface DemoLessonPayload { tipo: string; nome: string; numero_di_telefono: string; corso: string; giorno: string; orario: string }`; `export function sanitizeTemplateParam(value: string | null | undefined): string`; `export function buildNome(name: string | null | undefined, lastName: string | null | undefined): string`; `export interface BuildPayloadArgs { kind: DemoWebhookKind; nome: string; phoneE164: string; corso: string; startAtMillis: number; giorno?: string; orario?: string }`; `export function buildDemoLessonPayload(args: BuildPayloadArgs): DemoLessonPayload`

- [ ] **Step 1: Scrivi i test che falliscono**

`functions/src/__tests__/whatsappFormat.test.ts`:

```ts
import {
  MONTH_NAMES_IT,
  formatGiorno,
  formatOrario,
  isSameRomeDay,
  tomorrowRomeRange,
} from "../whatsapp/format";

// Europe/Rome 2026: CET (UTC+1) d'inverno; CEST (UTC+2) dal 29 mar al 25 ott.

describe("formatGiorno", () => {
  test("mese minuscolo con anno, senza giorno della settimana (inverno)", () => {
    expect(formatGiorno(Date.UTC(2026, 0, 15, 18, 0))).toBe("15 gennaio 2026");
  });

  test("data estiva", () => {
    expect(formatGiorno(Date.UTC(2026, 6, 15, 17, 0))).toBe("15 luglio 2026");
  });

  test("non zero-padda il giorno del mese", () => {
    expect(formatGiorno(Date.UTC(2026, 9, 3, 10, 0))).toBe("3 ottobre 2026");
  });

  test("usa il giorno di Roma, non quello UTC", () => {
    // 22:30 UTC del 1 luglio = 00:30 del 2 luglio a Roma.
    expect(formatGiorno(Date.UTC(2026, 6, 1, 22, 30))).toBe("2 luglio 2026");
  });

  test("copre tutti i dodici mesi", () => {
    expect(MONTH_NAMES_IT).toHaveLength(12);
    for (let m = 1; m <= 12; m++) {
      expect(formatGiorno(Date.UTC(2026, m - 1, 15, 12, 0))).toBe(
        `15 ${MONTH_NAMES_IT[m - 1]} 2026`
      );
    }
  });
});

describe("formatOrario", () => {
  test("mezzanotte è 00:00 e non 24:00", () => {
    expect(formatOrario(Date.UTC(2026, 6, 1, 22, 0))).toBe("00:00");
  });

  test("zero-padda ore e minuti", () => {
    expect(formatOrario(Date.UTC(2026, 0, 15, 8, 5))).toBe("09:05");
  });

  test("usa l'orologio di Roma in estate e in inverno", () => {
    expect(formatOrario(Date.UTC(2026, 6, 15, 16, 30))).toBe("18:30");
    expect(formatOrario(Date.UTC(2026, 0, 15, 17, 30))).toBe("18:30");
  });
});

describe("isSameRomeDay", () => {
  test("vero nello stesso giorno romano", () => {
    expect(isSameRomeDay(Date.UTC(2026, 6, 1, 22, 30), Date.UTC(2026, 6, 2, 20, 0))).toBe(true);
  });

  test("falso a cavallo della mezzanotte romana", () => {
    // 21:30 UTC = 23:30 del 1 luglio; 22:30 UTC = 00:30 del 2 luglio.
    expect(isSameRomeDay(Date.UTC(2026, 6, 1, 21, 30), Date.UTC(2026, 6, 1, 22, 30))).toBe(false);
  });
});

describe("tomorrowRomeRange", () => {
  test("giorno ordinario (CEST)", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 6, 1, 10))).toEqual({
      startMs: Date.UTC(2026, 6, 1, 22), // 2 luglio 00:00 CEST
      endMs: Date.UTC(2026, 6, 2, 22) - 1,
    });
  });

  test("domani è il giorno del fall-back: comprende la lezione delle 23:30", () => {
    const range = tomorrowRomeRange(Date.UTC(2026, 9, 24, 12));
    expect(range).toEqual({
      startMs: Date.UTC(2026, 9, 24, 22), // 25 ottobre 00:00 CEST
      endMs: Date.UTC(2026, 9, 25, 23) - 1, // 26 ottobre 00:00 CET
    });
    const lezione2330 = Date.UTC(2026, 9, 25, 22, 30); // 23:30 CET del 25
    expect(lezione2330).toBeGreaterThanOrEqual(range.startMs);
    expect(lezione2330).toBeLessThanOrEqual(range.endMs);
  });

  test("domani è il giorno dello spring-forward", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 2, 28, 12))).toEqual({
      startMs: Date.UTC(2026, 2, 28, 23), // 29 marzo 00:00 CET
      endMs: Date.UTC(2026, 2, 29, 22) - 1, // 30 marzo 00:00 CEST
    });
  });

  test("scavalca la fine del mese", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 9, 31, 12))).toEqual({
      startMs: Date.UTC(2026, 9, 31, 23), // 1 novembre 00:00 CET
      endMs: Date.UTC(2026, 10, 1, 23) - 1,
    });
  });
});
```

`functions/src/__tests__/whatsappPayload.test.ts`:

```ts
import {
  TIPO_BY_KIND,
  buildDemoLessonPayload,
  buildNome,
  sanitizeTemplateParam,
} from "../whatsapp/payload";

const base = {
  nome: "Mario Rossi",
  phoneE164: "+393331234567",
  corso: "Corso Excel Avanzato",
  // 15 ottobre 2026, 18:00 ora di Roma (CEST).
  startAtMillis: Date.UTC(2026, 9, 15, 16),
};

describe("sanitizeTemplateParam", () => {
  test("collassa spazi, newline e tab", () => {
    expect(sanitizeTemplateParam("  Pole\n  Dance\tBase    ")).toBe("Pole Dance Base");
  });

  test("gestisce null e undefined", () => {
    expect(sanitizeTemplateParam(null)).toBe("");
    expect(sanitizeTemplateParam(undefined)).toBe("");
  });
});

describe("buildNome", () => {
  test("unisce nome e cognome", () => {
    expect(buildNome("Mario", "Rossi")).toBe("Mario Rossi");
  });

  test("non lascia spazi con il cognome vuoto", () => {
    expect(buildNome("Mario", "")).toBe("Mario");
    expect(buildNome("Mario", null)).toBe("Mario");
  });

  test("è vuoto se mancano entrambi", () => {
    expect(buildNome(null, undefined)).toBe("");
  });
});

describe("buildDemoLessonPayload", () => {
  test("produce esattamente il body atteso dallo scenario Make", () => {
    expect(buildDemoLessonPayload({ ...base, kind: "booked" })).toEqual({
      tipo: "conferma",
      nome: "Mario Rossi",
      numero_di_telefono: "+393331234567",
      corso: "Corso Excel Avanzato",
      giorno: "15 ottobre 2026",
      orario: "18:00",
    });
  });

  test("espone esattamente sei chiavi (Make impara lo schema dal primo payload)", () => {
    expect(Object.keys(buildDemoLessonPayload({ ...base, kind: "reminder" })).sort()).toEqual([
      "corso",
      "giorno",
      "nome",
      "numero_di_telefono",
      "orario",
      "tipo",
    ]);
  });

  test("i due eventi differiscono solo per tipo", () => {
    const booked = buildDemoLessonPayload({ ...base, kind: "booked" });
    const reminder = buildDemoLessonPayload({ ...base, kind: "reminder" });
    expect(reminder.tipo).toBe("promemoria");
    expect({ ...booked, tipo: "" }).toEqual({ ...reminder, tipo: "" });
    expect(Object.keys(TIPO_BY_KIND).sort()).toEqual(["booked", "reminder"]);
  });

  test("non contiene mai la chiave di autenticazione", () => {
    const payload = buildDemoLessonPayload({ ...base, kind: "booked" }) as unknown as Record<string, unknown>;
    expect(payload.token).toBeUndefined();
    expect(payload.apiKey).toBeUndefined();
    expect(payload["Demo-Reminder"]).toBeUndefined();
  });

  test("sanifica nome e corso per i parametri del template", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      kind: "booked",
      nome: "  Mario   Rossi \n",
      corso: "Pole\tDance    Base",
    });
    expect(payload.nome).toBe("Mario Rossi");
    expect(payload.corso).toBe("Pole Dance Base");
    for (const value of Object.values(payload)) {
      expect(value).not.toMatch(/[\n\t]| {4}/);
    }
  });

  test("usa giorno e orario passati esplicitamente (callable di prova)", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      kind: "booked",
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
    expect(payload.giorno).toBe("28 aprile 2026");
    expect(payload.orario).toBe("10:00");
  });

  test("ricade sulla data della lezione se giorno e orario sono vuoti", () => {
    const payload = buildDemoLessonPayload({ ...base, kind: "booked", giorno: " ", orario: "" });
    expect(payload.giorno).toBe("15 ottobre 2026");
    expect(payload.orario).toBe("18:00");
  });

  test("rifiuta un campo vuoto invece di mandarlo a Make", () => {
    expect(() => buildDemoLessonPayload({ ...base, kind: "booked", nome: "" })).toThrow(/nome/);
    expect(() => buildDemoLessonPayload({ ...base, kind: "booked", corso: "   " })).toThrow(/corso/);
  });
});
```

- [ ] **Step 2: Verifica che falliscano**

Run: `cd functions && npx jest src/__tests__/whatsappFormat.test.ts src/__tests__/whatsappPayload.test.ts`
Expected: FAIL con `Cannot find module '../whatsapp/format'` e `'../whatsapp/payload'`

- [ ] **Step 3: Implementa `format.ts`**

`functions/src/whatsapp/format.ts`:

```ts
// Date e orari del body WhatsApp nel fuso Europe/Rome.
//
// Riusa gli helper di enrollment/notify.ts invece di aggiungere una quarta
// implementazione dell'offset di Roma. La conversione wall-clock → UTC di
// notify.ts è a passo singolo, ma a mezzanotte è esatta: in Europa l'ora
// cambia alle 01:00 UTC, quindi mai tra la mezzanotte locale e la mezzanotte UTC.

import { romeParts, romeWallClockToUtcMillis } from "../enrollment/notify";

/** Mesi in italiano, minuscoli: è il formato atteso dallo scenario Make. */
export const MONTH_NAMES_IT = [
  "gennaio",
  "febbraio",
  "marzo",
  "aprile",
  "maggio",
  "giugno",
  "luglio",
  "agosto",
  "settembre",
  "ottobre",
  "novembre",
  "dicembre",
];

/** `"15 ottobre 2026"` — campo `giorno` del body. */
export function formatGiorno(millis: number): string {
  const p = romeParts(millis);
  return `${p.day} ${MONTH_NAMES_IT[p.month - 1]} ${p.year}`;
}

/** `"18:00"` — campo `orario` del body (solo l'ora di inizio). */
export function formatOrario(millis: number): string {
  const p = romeParts(millis);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

/** `true` se i due istanti cadono nello stesso giorno civile di Roma. */
export function isSameRomeDay(aMillis: number, bMillis: number): boolean {
  const a = romeParts(aMillis);
  const b = romeParts(bMillis);
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

export interface RomeDayRange {
  startMs: number;
  endMs: number;
}

/** Intervallo UTC `[00:00, 23:59:59.999]` ora di Roma del giorno dopo `nowMillis`. */
export function tomorrowRomeRange(nowMillis: number): RomeDayRange {
  const p = romeParts(nowMillis);
  // Date.UTC normalizza day+1 / day+2 oltre la fine del mese.
  return {
    startMs: romeWallClockToUtcMillis(p.year, p.month, p.day + 1, 0, 0),
    endMs: romeWallClockToUtcMillis(p.year, p.month, p.day + 2, 0, 0) - 1,
  };
}
```

- [ ] **Step 4: Implementa `payload.ts`**

`functions/src/whatsapp/payload.ts`:

```ts
// Body del Custom webhook Make. È un CONTRATTO con lo scenario: Make impara lo
// schema dal primo payload, quindi aggiungere o rinominare una chiave richiede
// un "Redetermine data structure" lato Make, altrimenti il campo non è
// selezionabile nei moduli a valle. La chiave di autenticazione NON sta qui:
// viaggia nell'header `Demo-Reminder` (makeClient.ts).

import { formatGiorno, formatOrario } from "./format";

export type DemoWebhookKind = "booked" | "reminder";

/** Valore del campo `tipo`, su cui il Router di Make sceglie il template. */
export const TIPO_BY_KIND: Record<DemoWebhookKind, string> = {
  booked: "conferma",
  reminder: "promemoria",
};

export interface DemoLessonPayload {
  tipo: string;
  nome: string;
  numero_di_telefono: string;
  corso: string;
  giorno: string;
  orario: string;
}

/**
 * I parametri dei template WhatsApp non ammettono newline, tab né 4+ spazi
 * consecutivi (Meta rifiuta il messaggio): collasso ogni spazio bianco in uno.
 */
export function sanitizeTemplateParam(value: string | null | undefined): string {
  if (value === null || value === undefined) return "";
  return value.replace(/\s+/g, " ").trim();
}

/** `"Mario Rossi"` da nome e cognome, tollerando l'assenza del cognome. */
export function buildNome(
  name: string | null | undefined,
  lastName: string | null | undefined
): string {
  return sanitizeTemplateParam(`${name ?? ""} ${lastName ?? ""}`);
}

export interface BuildPayloadArgs {
  kind: DemoWebhookKind;
  nome: string;
  phoneE164: string;
  corso: string;
  startAtMillis: number;
  /** Override della data formattata: solo per la callable di prova. */
  giorno?: string;
  /** Override dell'orario formattato: solo per la callable di prova. */
  orario?: string;
}

/**
 * Costruisce il body. I chiamanti scartano a monte chi non ha nome o telefono:
 * un campo vuoto qui è un bug da far emergere, non un caso da inviare.
 */
export function buildDemoLessonPayload(args: BuildPayloadArgs): DemoLessonPayload {
  const payload: DemoLessonPayload = {
    tipo: TIPO_BY_KIND[args.kind],
    nome: sanitizeTemplateParam(args.nome),
    numero_di_telefono: args.phoneE164,
    corso: sanitizeTemplateParam(args.corso),
    giorno: sanitizeTemplateParam(args.giorno) || formatGiorno(args.startAtMillis),
    orario: sanitizeTemplateParam(args.orario) || formatOrario(args.startAtMillis),
  };

  for (const [key, value] of Object.entries(payload)) {
    if (value === "") {
      throw new Error(
        `Campo "${key}" vuoto nel payload Make: i parametri del template WhatsApp non ammettono valori vuoti`
      );
    }
  }
  return payload;
}
```

- [ ] **Step 5: Verifica che passino**

Run: `cd functions && npx jest src/__tests__/whatsappFormat.test.ts src/__tests__/whatsappPayload.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add functions/src/whatsapp/format.ts functions/src/whatsapp/payload.ts functions/src/__tests__/whatsappFormat.test.ts functions/src/__tests__/whatsappPayload.test.ts
git commit -m "feat(whatsapp): formati data/ora di Roma e payload verso Make"
```

---

### Task 4: Gate di ambiente (`WHATSAPP_DEMO_MODE` e allowlist di staging)

**Files:**
- Create: `functions/src/whatsapp/environment.ts`
- Test: `functions/src/__tests__/whatsappEnvironment.test.ts`

**Interfaces:**
- Consumes: `normalizePhoneE164` da `functions/src/whatsapp/phone.ts`
- Produces: `export type WhatsappDemoMode = "off" | "test" | "live"`; `export function whatsappDemoMode(env: NodeJS.ProcessEnv): WhatsappDemoMode`; `export function isWhatsappRecipientAllowed(e164: string, env: NodeJS.ProcessEnv): boolean`

- [ ] **Step 1: Scrivi il test che fallisce**

`functions/src/__tests__/whatsappEnvironment.test.ts`:

```ts
import { isWhatsappRecipientAllowed, whatsappDemoMode } from "../whatsapp/environment";

describe("whatsappDemoMode", () => {
  test.each([
    [undefined, "off"],
    ["", "off"],
    ["off", "off"],
    ["si", "off"],
    ["test", "test"],
    ["live", "live"],
    [" LIVE ", "live"],
  ])("WHATSAPP_DEMO_MODE=%p → %s", (raw, expected) => {
    const env: NodeJS.ProcessEnv = raw === undefined ? {} : { WHATSAPP_DEMO_MODE: raw };
    expect(whatsappDemoMode(env)).toBe(expected);
  });
});

describe("isWhatsappRecipientAllowed", () => {
  test("fuori da staging ogni numero è ammesso", () => {
    expect(isWhatsappRecipientAllowed("+393331234567", {})).toBe(true);
  });

  test("su staging senza allowlist non passa nessuno", () => {
    expect(isWhatsappRecipientAllowed("+393331234567", { APP_ENV: "staging" })).toBe(false);
  });

  test("su staging passa solo chi è in allowlist, anche se scritto senza prefisso", () => {
    const env = {
      APP_ENV: "staging",
      STAGING_WHATSAPP_ALLOWLIST: " 333 123 4567 , +41791234567 ",
    };
    expect(isWhatsappRecipientAllowed("+393331234567", env)).toBe(true);
    expect(isWhatsappRecipientAllowed("+41791234567", env)).toBe(true);
    expect(isWhatsappRecipientAllowed("+393339876543", env)).toBe(false);
  });
});
```

- [ ] **Step 2: Verifica che fallisca**

Run: `cd functions && npx jest src/__tests__/whatsappEnvironment.test.ts`
Expected: FAIL con `Cannot find module '../whatsapp/environment'`

- [ ] **Step 3: Implementa `environment.ts`**

`functions/src/whatsapp/environment.ts`:

```ts
// Cosa esiste e a chi si può scrivere, in base all'ambiente.
//
// WHATSAPP_DEMO_MODE (in `.env.<projectId>`, letta dalla CLI prima della
// discovery degli export, come i gate dei certificati in index.ts):
//   off  (default, e per qualunque valore sconosciuto) → niente WhatsApp;
//   test → solo la callable di prova (Admin), per verificare lo scenario Make;
//   live → + conferma all'iscrizione + cron dei promemoria.
//
// Su staging i dati possono essere un clone della produzione, con numeri reali:
// lì un numero passa solo se è in STAGING_WHATSAPP_ALLOWLIST (lista separata da
// virgole, anche senza prefisso: viene normalizzata).

import { normalizePhoneE164 } from "./phone";

export type WhatsappDemoMode = "off" | "test" | "live";

export function whatsappDemoMode(env: NodeJS.ProcessEnv): WhatsappDemoMode {
  const raw = (env.WHATSAPP_DEMO_MODE ?? "").trim().toLowerCase();
  return raw === "test" || raw === "live" ? raw : "off";
}

export function isWhatsappRecipientAllowed(e164: string, env: NodeJS.ProcessEnv): boolean {
  if (env.APP_ENV !== "staging") return true;
  const allowed = (env.STAGING_WHATSAPP_ALLOWLIST ?? "")
    .split(",")
    .map((entry) => normalizePhoneE164(entry).e164)
    .filter((entry): entry is string => entry !== null);
  return allowed.includes(e164);
}
```

- [ ] **Step 4: Verifica che passi**

Run: `cd functions && npx jest src/__tests__/whatsappEnvironment.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add functions/src/whatsapp/environment.ts functions/src/__tests__/whatsappEnvironment.test.ts
git commit -m "feat(whatsapp): gate WHATSAPP_DEMO_MODE e allowlist numeri su staging"
```

---

### Task 5: Client HTTP verso Make

**Files:**
- Create: `functions/src/whatsapp/makeClient.ts`
- Test: `functions/src/__tests__/whatsappMakeClient.test.ts`

**Interfaces:**
- Consumes: `DemoLessonPayload` da `functions/src/whatsapp/payload.ts`
- Produces: `export const MAKE_AUTH_HEADER = "Demo-Reminder"`; `export interface PostResult { ok: boolean; status: number }`; `export async function postToMake(url: string, apiKey: string, payload: DemoLessonPayload, opts?: { timeoutMs?: number }): Promise<PostResult>`, che non lancia mai. `status: 0` significa **esito incerto**, perché la richiesta potrebbe essere arrivata a Make prima del timeout.

- [ ] **Step 1: Scrivi il test che fallisce**

`functions/src/__tests__/whatsappMakeClient.test.ts`:

```ts
import { MAKE_AUTH_HEADER, postToMake } from "../whatsapp/makeClient";
import { DemoLessonPayload } from "../whatsapp/payload";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const WEBHOOK_URL = "https://hook.eu1.make.com/abc123secrettoken";
const API_KEY = "chiave-super-segreta";
const payload: DemoLessonPayload = {
  tipo: "promemoria",
  nome: "Mario Rossi",
  numero_di_telefono: "+393331234567",
  corso: "Corso Excel Avanzato",
  giorno: "15 ottobre 2026",
  orario: "18:00",
};

let fetchMock: jest.Mock;

beforeEach(() => {
  fetchMock = jest.fn();
  (global as Record<string, unknown>).fetch = fetchMock;
});

afterEach(() => jest.clearAllMocks());

/** Make risponde con il testo "Accepted", non con JSON. */
function mockStatus(status: number) {
  fetchMock.mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => "Accepted",
  });
}

function allLoggedText(): string {
  const { logger } = jest.requireMock("firebase-functions");
  return ["info", "warn", "error"]
    .flatMap((level) => (logger[level] as jest.Mock).mock.calls)
    .map((call) => JSON.stringify(call))
    .join("\n");
}

describe("postToMake", () => {
  test("manda la chiave nell'header Demo-Reminder e non nel body", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, API_KEY, payload);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(WEBHOOK_URL);
    expect(init.method).toBe("POST");
    expect(init.headers[MAKE_AUTH_HEADER]).toBe(API_KEY);
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.body).toBe(JSON.stringify(payload));
    expect(init.body).not.toContain(API_KEY);
  });

  test("imposta un timeout sulla richiesta", async () => {
    mockStatus(200);
    await postToMake(WEBHOOK_URL, API_KEY, payload, { timeoutMs: 500 });
    expect(fetchMock.mock.calls[0][1].signal).toBeDefined();
  });

  test("200 testuale → ok, senza deserializzare il corpo", async () => {
    mockStatus(200);
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: true,
      status: 200,
    });
  });

  test("risposta di errore → ok:false, senza lanciare", async () => {
    mockStatus(410); // scenario Make disattivato
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: false,
      status: 410,
    });
  });

  test("errore di rete o timeout → ok:false con status 0, senza lanciare", async () => {
    fetchMock.mockRejectedValue(new Error("The operation was aborted due to timeout"));
    await expect(postToMake(WEBHOOK_URL, API_KEY, payload)).resolves.toEqual({
      ok: false,
      status: 0,
    });
  });

  test("non scrive mai URL né chiave nei log, ma scrive l'host", async () => {
    mockStatus(500);
    await postToMake(WEBHOOK_URL, API_KEY, payload);
    fetchMock.mockRejectedValue(new Error(`connect ECONNREFUSED ${WEBHOOK_URL} key=${API_KEY}`));
    await postToMake(WEBHOOK_URL, API_KEY, payload);

    const logged = allLoggedText();
    expect(logged).not.toContain(WEBHOOK_URL);
    expect(logged).not.toContain(API_KEY);
    expect(logged).toContain("hook.eu1.make.com");
  });
});
```

- [ ] **Step 2: Verifica che fallisca**

Run: `cd functions && npx jest src/__tests__/whatsappMakeClient.test.ts`
Expected: FAIL con `Cannot find module '../whatsapp/makeClient'`

- [ ] **Step 3: Implementa `makeClient.ts`**

`functions/src/whatsapp/makeClient.ts`:

```ts
// Unica chiamata HTTP verso il Custom webhook Make.
//
// Non lancia mai: un invio fallito è un esito normale che cron e iscrizione
// devono poter attraversare. Non deserializza la risposta: Make risponde
// "Accepted" in testo, e gli errori a valle (numero non su WhatsApp, template
// non approvato, credito esaurito) non tornano comunque indietro.

import { logger } from "firebase-functions";
import { DemoLessonPayload } from "./payload";

/** Header su cui lo scenario Make filtra le richieste. */
export const MAKE_AUTH_HEADER = "Demo-Reminder";

/**
 * undici (il fetch di Node) non ha un timeout breve di default: senza questo
 * uno scenario appeso bloccherebbe cron e iscrizione per minuti.
 */
const DEFAULT_TIMEOUT_MS = 10_000;

export interface PostResult {
  ok: boolean;
  /** Status HTTP; `0` se manca una risposta (invio potenzialmente già accettato). */
  status: number;
}

/** Solo l'host: l'URL completo contiene il token del webhook. */
function safeHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return "unknown";
  }
}

function scrubSecrets(message: string, secrets: string[]): string {
  let out = message;
  for (const secret of secrets) {
    if (secret) out = out.split(secret).join("[redacted]");
  }
  return out;
}

export async function postToMake(
  url: string,
  apiKey: string,
  payload: DemoLessonPayload,
  opts: { timeoutMs?: number } = {}
): Promise<PostResult> {
  const host = safeHost(url);
  let response: Awaited<ReturnType<typeof fetch>>;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        [MAKE_AUTH_HEADER]: apiKey,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
  } catch (err) {
    logger.error("Chiamata al webhook Make fallita", {
      host,
      tipo: payload.tipo,
      error: scrubSecrets(err instanceof Error ? err.message : String(err), [url, apiKey]),
    });
    return { ok: false, status: 0 };
  }

  if (!response.ok) {
    logger.error("Webhook Make ha risposto con errore", {
      host,
      status: response.status,
      tipo: payload.tipo,
    });
    return { ok: false, status: response.status };
  }

  logger.info("Webhook Make chiamato", { host, status: response.status, tipo: payload.tipo });
  return { ok: true, status: response.status };
}
```

- [ ] **Step 4: Verifica che passi**

Run: `cd functions && npx jest src/__tests__/whatsappMakeClient.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add functions/src/whatsapp/makeClient.ts functions/src/__tests__/whatsappMakeClient.test.ts
git commit -m "feat(whatsapp): client verso il webhook Make con header Demo-Reminder"
```

---

### Task 6: Registro degli invii (idempotenza) e fake Firestore per i test

**Files:** creare functions/src/whatsapp/sendLog.ts, functions/src/__tests__/helpers/whatsappFakeDb.ts e functions/src/__tests__/whatsappSendLog.test.ts.

**Interfacce:**

- DEMO_LOG_COLLECTION = "demoLessonWebhookLog"; demoLogDocId(kind, userId, courseId) conserva gli ID già usati nel branch di riferimento: kind_userId_courseId.
- claimSend(db, kind, userId, courseId, nowMillis) restituisce "claimed", "sent" oppure "needs_review". Usa create() atomico. Se il documento esiste, legge ok/outcome: solo ok === true significa "sent"; ogni altro stato, compresi i documenti legacy senza ok, significa "needs_review".
- markSendOutcome(db, kind, userId, courseId, outcome, status?) aggiorna il claim: outcome è "sent", "rejected" o "unknown"; ok è true solo per "sent". Registra status HTTP solo se disponibile, senza telefono, email, URL o chiave. Il claim appena creato ha outcome "pending", ok false e sentAt; non si cancella automaticamente.
- wasNotifiedToday(db, userId, courseId, noticeDayMillis) restituisce true soltanto quando il documento "booked" ha ok === true e sentAt cade nello stesso giorno di Roma. Un claim pending/unknown/rejected non sopprime il promemoria.

- [ ] **Step 1: Crea il fake Firestore.** Mantieni la forma usata nei Task 7–9: Store/Data, query where (==, >=, <=, array-contains-any), limit/get, doc create/get/update, whereCalls e ops. Il fake deve simulare ALREADY_EXISTS su create e poter simulare errori di create/update. Per il test di ripresa conserva lo Store mutato dal primo run e passalo al secondo fake, senza tornare alla fixture iniziale.

- [ ] **Step 2: Scrivi i test che falliscono.** Copri creazione atomica e struttura senza dati personali; conferma riuscita; secondo claim su sent; secondo claim su pending, unknown, rejected e documento legacy senza ok; errore Firestore diverso da ALREADY_EXISTS; wasNotifiedToday nello stesso giorno e a cavallo della mezzanotte di Roma; nessuna soppressione con ok false o assente. Un claim rimasto pending dopo un'interruzione deve richiedere verifica, senza nuovo POST.

- [ ] **Step 3: Implementa sendLog.ts e verifica.** Non usare delete() per rendere ritentabile un invio incerto: Make può averlo già accettato. Gli errori di update dopo una risposta 2xx lasciano il claim pending e vanno loggati come da verificare. Test: npm run build e npx jest src/__tests__/whatsappSendLog.test.ts.

- [ ] **Step 4: Commit.** Aggiungi per nome i tre file del task e usa il messaggio feat(whatsapp): registro invii con esiti verificabili.

---

### Task 7: Destinatario, invio e conferma WhatsApp

**Files:** creare functions/src/whatsapp/demoLesson.ts e functions/src/__tests__/whatsappDemoLesson.test.ts.

**Interfacce:** conserva DemoUser, DemoCourse, WhatsappDeps, SendOutcome, mapDemoUserDoc, mapDemoCourseDoc, checkRecipient, dispatchDemoLesson e notifyDemoLessonBooked. WhatsappDeps accetta anche wait?: (ms: number) => Promise<void>, usata nei test senza attese reali. dispatchDemoLesson accetta un ultimo parametro facoltativo noticeDayMillis; per il cron è l'istante schedulato, per la conferma usa deps.nowMillis.

- [ ] **Step 1: Scrivi i test che falliscono.** Copri mapping e fallback UID; utente attivo con mobile valido; assenza di numero/nome/corso/data, corso passato, reminderEnabled false, staging fuori allowlist; un solo invio riuscito; 429, 429, 200 con tre POST e un solo claim; tre 429 con esito rejected; 410 con una POST e rejected; timeout/status 0, HTTP 5xx ed eccezione di post con una sola POST e unknown; secondo tentativo su sent senza POST e su pending/unknown/rejected con reason needs_review. La conferma legge utente e corso da Firestore e mantiene il lookup del corso per uid.

- [ ] **Step 2: Implementa la selezione del destinatario.** Riusa gli helper dei Task 2–4 e le regole originali: isActive, corso futuro, flag reminderEnabled solo per promemoria, nome/corso non vuoti, mobile plausibile, allowlist staging. La decisione "utente di prova" resta al chiamante.

- [ ] **Step 3: Implementa dispatchDemoLesson.** Dopo le guardie, sopprimi il promemoria solo se wasNotifiedToday trova una conferma riuscita. Acquisisci il claim prima della POST. Se il claim è sent, restituisci already_sent; se è needs_review, restituisci failed: true e reason needs_review, senza POST. Con 2xx marca sent. Con 429 fai al massimo due nuovi tentativi sotto lo stesso claim, attendendo 250 ms e poi 1000 ms; wait usa setTimeout di default e l'iniezione dei test evita attese reali. Dopo il terzo 429 marca rejected. Con altri 4xx marca rejected senza retry. Con status 0, 5xx o eccezione di post marca unknown senza retry. Se markSendOutcome fallisce dopo la POST, non ripetere la POST: logga il claim pending e restituisci failed: true, reason needs_review. Ogni log contiene solo kind, userId, courseId, outcome/status e motivo, mai payload, numero o secret.

- [ ] **Step 4: Implementa notifyDemoLessonBooked.** Rileggi utente e corso dopo l'iscrizione committata, chiama dispatchDemoLesson con kind booked, registra il motivo degli scarti. Mantieni l'esito best-effort di EnrollmentDeps.

- [ ] **Step 5: Verifica e commit.** npm run build; npx jest src/__tests__/whatsappDemoLesson.test.ts src/__tests__/whatsappSendLog.test.ts. Aggiungi per nome i due file del task.

---

### Task 8: Cron dei promemoria della sera prima

**Files:** creare functions/src/whatsapp/reminders.ts e functions/src/__tests__/whatsappReminders.test.ts.

**Interfacce:** conserva ARRAY_CONTAINS_ANY_LIMIT = 30, chunk e ReminderRunResult. Esporta MAX_CONCURRENT_SENDS = 10 e runDemoLessonReminders(deps, options), dove options contiene scheduledAtMillis, deadlineMillis e now?: () => number (default Date.now). Il giorno dei corsi e la soppressione della conferma usano scheduledAtMillis; deadlineMillis e now governano solo il budget del run.

- [ ] **Step 1: Scrivi i test che falliscono.** Copri filtri Firestore a campo singolo, utenti V2 e legacy, cliente convertito, snapshot malformato isolato, reminderEnabled false, 31 corsi in due query senza utente duplicato e due messaggi per due corsi, conferma sent nello stesso giorno, claim pending che non sopprime il promemoria ma viene contato come failed/needs_review, HTTP 429 ritentato nel run, timeout/5xx con un solo POST. Con promesse controllate verifica che non ci siano più di 10 POST contemporanee. Simula deadline raggiunta dopo alcuni invii: il run deve fallire dopo gli invii in corso; un secondo run con lo stesso scheduledAtMillis e lo stesso Store invia solo i candidati ancora senza claim riuscito. Ripeti la ripresa attraversando la mezzanotte UTC e quella di Roma.

- [ ] **Step 2: Implementa la selezione.** Usa tomorrowRomeRange(scheduledAtMillis) sui corsi; interroga users.courses con array-contains-any a blocchi di 30; deduplica per document ID; valida snapshotRecords per utente, continua sugli snapshot illeggibili; applica isTrialUser e genera una coppia candidato per ogni corso di domani presente in user.courses.

- [ ] **Step 3: Implementa il pool limitato.** Avvia al massimo 10 worker. Prima di prelevare ogni nuovo candidato, confronta options.now() con deadlineMillis. Quando la deadline è raggiunta, non avviare altri invii, attendi quelli già avviati, logga il riepilogo e lancia un errore affinché Cloud Scheduler ritenti l'evento. I singoli esiti unknown/rejected/needs_review incrementano failed e vengono loggati, ma non rilanciano l'intero batch; la verifica è manuale. I sent/skipped restano idempotenti sul retry del job.

- [ ] **Step 4: Verifica e commit.** npm run build; npx jest src/__tests__/whatsappReminders.test.ts src/__tests__/whatsappDemoLesson.test.ts. Aggiungi per nome i due file del task.

---

### Task 9: Callable di prova, solo Admin

**Files:**
- Create: `functions/src/whatsapp/testWebhook.ts`
- Test: `functions/src/__tests__/whatsappTestWebhook.test.ts`

**Interfaces:**
- Consumes: `HandlerRequest` da `functions/src/handler.ts` (`{ auth?: { uid: string } | null; data: unknown }`); `isWhatsappRecipientAllowed` (Task 4); `normalizePhoneE164` (Task 2); `buildDemoLessonPayload`, `sanitizeTemplateParam`, `DemoWebhookKind` (Task 3); `WhatsappDeps` (Task 7)
- Produces: `export async function sendTestDemoLessonWebhookHandler(request: HandlerRequest, deps: WhatsappDeps): Promise<Record<string, unknown>>`, che ritorna `{ ok, status, payload }`

- [ ] **Step 1: Scrivi il test che fallisce**

`functions/src/__tests__/whatsappTestWebhook.test.ts`:

```ts
import { WhatsappDeps } from "../whatsapp/demoLesson";
import { sendTestDemoLessonWebhookHandler } from "../whatsapp/testWebhook";
import { makeWhatsappDb } from "./helpers/whatsappFakeDb";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const NOW = Date.UTC(2026, 9, 14, 17); // domani alle 19:00 → "15 ottobre 2026", "19:00"

function setup(env: NodeJS.ProcessEnv = {}) {
  const fake = makeWhatsappDb({
    users: { admin: { role: "Admin" }, trainer: { role: "Trainer" }, member: { role: "User" } },
  });
  const post = jest.fn().mockResolvedValue({ ok: true, status: 200 });
  const deps: WhatsappDeps = {
    db: fake.db,
    webhookUrl: "https://hook.eu1.make.com/abc",
    apiKey: "chiave",
    post,
    nowMillis: NOW,
    env,
  };
  return { deps, post };
}

const asAdmin = (data: unknown) => ({ auth: { uid: "admin" }, data });

afterEach(() => jest.clearAllMocks());

describe("sendTestDemoLessonWebhookHandler", () => {
  test("rifiuta le chiamate non autenticate", async () => {
    const { deps } = setup();
    await expect(
      sendTestDemoLessonWebhookHandler({ data: { numeroTelefono: "3331234567" } }, deps)
    ).rejects.toMatchObject({ code: "unauthenticated" });
  });

  test.each([["trainer"], ["member"], ["sconosciuto"]])(
    "nega a %s: servono i permessi Admin",
    async (uid) => {
      const { deps, post } = setup();
      await expect(
        sendTestDemoLessonWebhookHandler(
          { auth: { uid }, data: { numeroTelefono: "3331234567" } },
          deps
        )
      ).rejects.toMatchObject({ code: "permission-denied" });
      expect(post).not.toHaveBeenCalled();
    }
  );

  test("richiede il numero di telefono", async () => {
    const { deps } = setup();
    await expect(sendTestDemoLessonWebhookHandler(asAdmin({}), deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  test("rifiuta un numero non valido spiegando il motivo", async () => {
    const { deps } = setup();
    await expect(
      sendTestDemoLessonWebhookHandler(asAdmin({ numeroTelefono: "n/d" }), deps)
    ).rejects.toThrow(/not_numeric/);
  });

  test("su staging rifiuta i numeri fuori allowlist", async () => {
    const { deps, post } = setup({ APP_ENV: "staging" });
    await expect(
      sendTestDemoLessonWebhookHandler(asAdmin({ numeroTelefono: "3331234567" }), deps)
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(post).not.toHaveBeenCalled();
  });

  test("manda un payload con i default al numero indicato e lo restituisce", async () => {
    const { deps, post } = setup();
    const res = await sendTestDemoLessonWebhookHandler(
      asAdmin({ kind: "reminder", numeroTelefono: "3339876543" }),
      deps
    );
    const expected = {
      tipo: "promemoria",
      nome: "Test Test",
      numero_di_telefono: "+393339876543",
      corso: "Lezione di prova",
      giorno: "15 ottobre 2026",
      orario: "19:00",
    };
    expect(post.mock.calls[0][2]).toEqual(expected);
    expect(res).toEqual({ ok: true, status: 200, payload: expected });
  });

  test("usa nome, corso, giorno e orario passati dal chiamante", async () => {
    const { deps, post } = setup();
    await sendTestDemoLessonWebhookHandler(
      asAdmin({
        numeroTelefono: "3339876543",
        nome: "Mario Rossi",
        corso: "Pole Dance Base",
        giorno: "28 aprile 2026",
        orario: "10:00",
      }),
      deps
    );
    expect(post.mock.calls[0][2]).toMatchObject({
      tipo: "conferma",
      nome: "Mario Rossi",
      corso: "Pole Dance Base",
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
  });
});
```

- [ ] **Step 2: Verifica che fallisca**

Run: `cd functions && npx jest src/__tests__/whatsappTestWebhook.test.ts`
Expected: FAIL con `Cannot find module '../whatsapp/testWebhook'`

- [ ] **Step 3: Implementa `testWebhook.ts`**

`functions/src/whatsapp/testWebhook.ts`:

```ts
// Callable di prova (DebugEmailPage): manda un payload sintetico al numero
// indicato, senza toccare iscrizioni né registro invii. Serve a far apprendere
// lo schema a Make e a provare i template sul proprio telefono.
//
// Solo Admin: la callable è raggiungibile via HTTP da qualunque utente
// autenticato, e ogni WhatsApp è reale e a pagamento.

import { HttpsError } from "firebase-functions/v2/https";
import { HandlerRequest } from "../handler";
import { WhatsappDeps } from "./demoLesson";
import { isWhatsappRecipientAllowed } from "./environment";
import { DemoWebhookKind, buildDemoLessonPayload, sanitizeTemplateParam } from "./payload";
import { normalizePhoneE164 } from "./phone";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

interface TestPayload {
  numeroTelefono?: string;
  kind?: string;
  nome?: string;
  corso?: string;
  giorno?: string;
  orario?: string;
}

export async function sendTestDemoLessonWebhookHandler(
  request: HandlerRequest,
  deps: WhatsappDeps
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }
  const callerSnap = await deps.db.collection("users").doc(request.auth.uid).get();
  const role = (callerSnap.data()?.role as string | undefined) ?? null;
  if (role !== "Admin") {
    throw new HttpsError("permission-denied", "Solo gli Admin possono inviare WhatsApp di prova");
  }

  const payload = request.data as TestPayload | null;
  if (!payload || typeof payload !== "object" || !payload.numeroTelefono) {
    throw new HttpsError("invalid-argument", "numeroTelefono obbligatorio");
  }
  const phone = normalizePhoneE164(payload.numeroTelefono);
  if (phone.e164 === null) {
    throw new HttpsError("invalid-argument", `Numero non valido (${phone.reason})`);
  }
  if (!isWhatsappRecipientAllowed(phone.e164, deps.env)) {
    throw new HttpsError("permission-denied", "Numero non presente in STAGING_WHATSAPP_ALLOWLIST");
  }

  const kind: DemoWebhookKind = payload.kind === "reminder" ? "reminder" : "booked";
  const body = buildDemoLessonPayload({
    kind,
    nome: sanitizeTemplateParam(payload.nome) || "Test Test",
    corso: sanitizeTemplateParam(payload.corso) || "Lezione di prova",
    phoneE164: phone.e164,
    // Domani a quest'ora: una data plausibile per il messaggio di prova.
    startAtMillis: deps.nowMillis + ONE_DAY_MS,
    giorno: payload.giorno,
    orario: payload.orario,
  });

  const result = await deps.post(deps.webhookUrl, deps.apiKey, body);
  return { ok: result.ok, status: result.status, payload: { ...body } };
}
```

- [ ] **Step 4: Verifica che passi**

Run: `cd functions && npx jest src/__tests__/whatsappTestWebhook.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add functions/src/whatsapp/testWebhook.ts functions/src/__tests__/whatsappTestWebhook.test.ts
git commit -m "feat(whatsapp): callable di prova riservata agli Admin"
```

---

### Task 10: Conferma WhatsApp nell'iscrizione server-side

Area sensibile: leggi `lib/api/courses/README_ISCRIZIONI.md` prima di iniziare. A fine task chiedi una revisione all'agente `fitrope-enrollment-reviewer`.

**Files:**
- Modify: `functions/src/enrollment/enrollment.ts` (interfaccia `EnrollmentDeps`, oggi righe 48-53; blocco `if (isTrialUser)`, oggi righe 573-584)
- Modify: `lib/api/courses/README_ISCRIZIONI.md` (riga 18 della tabella; paragrafo alle righe 142-145)
- Test: `functions/src/__tests__/enrollmentHandlers.test.ts`

**Interfaces:**
- Consumes: le fixture già presenti in `enrollmentHandlers.test.ts`: `NOW`, `course()`, `packUser()`, `subUser()`, `trialSubDoc()`, `snapshotEntry()`, `openFreqSubDoc()`, `auth()`, `makeDb()`, `FakeStore`
- Produces: `EnrollmentDeps.notifyTrialWhatsapp?: (userId: string, courseId: string) => Promise<void>`, invocata best-effort solo quando `isTrialUser` è vero

- [ ] **Step 1: Scrivi i test che falliscono**

In `functions/src/__tests__/enrollmentHandlers.test.ts`, dentro `describe("subscribeToCourseHandler", …)`, inserisci subito dopo la chiusura `});` del test `"piano Prova V2 conserva conferma e promemoria"`:

```ts
  test("piano Prova V2: parte anche il WhatsApp di conferma", async () => {
    const whatsapp: Array<[string, string]> = [];
    const trial = trialSubDoc(1);
    const store: FakeStore = {
      users: {
        u1: subUser({
          subscriptionModelVersion: 2,
          activeSubscriptions: [snapshotEntry("trial", trial)],
        }),
      },
      courses: { c1: course() },
      subs: { trial },
    };
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb(store),
      { notifyTrialWhatsapp: async (u, c) => void whatsapp.push([u, c]) },
      NOW
    );
    expect(whatsapp).toEqual([["u1", "c1"]]);
  });

  test("PROVA legacy: parte il WhatsApp di conferma", async () => {
    const whatsapp: string[] = [];
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb({
        users: { u1: packUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA", entrateDisponibili: 1 }) },
        courses: { c1: course() },
        subs: {},
      }),
      { notifyTrialWhatsapp: async (u) => void whatsapp.push(u) },
      NOW
    );
    expect(whatsapp).toEqual(["u1"]);
  });

  test("PROVA convertito al multi-abbonamento: nessun WhatsApp", async () => {
    const whatsapp: string[] = [];
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb({
        users: {
          u1: subUser({
            tipologiaIscrizione: "ABBONAMENTO_PROVA",
            activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
          }),
        },
        courses: { c1: course() },
        subs: { "sub-open": openFreqSubDoc(2) },
      }),
      { notifyTrialWhatsapp: async (u) => void whatsapp.push(u) },
      NOW
    );
    expect(whatsapp).toEqual([]);
  });

  test("utente non PROVA: nessun WhatsApp", async () => {
    const whatsapp: string[] = [];
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb({ users: { u1: packUser() }, courses: { c1: course() }, subs: {} }),
      { notifyTrialWhatsapp: async (u) => void whatsapp.push(u) },
      NOW
    );
    expect(whatsapp).toEqual([]);
  });

  test("WhatsApp che fallisce non fa fallire l'iscrizione né le altre notifiche", async () => {
    const calls: string[] = [];
    const result = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb({
        users: { u1: packUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA", entrateDisponibili: 1 }) },
        courses: { c1: course() },
        subs: {},
      }),
      {
        notifyTrialConfirmation: async () => void calls.push("confirmation"),
        notifyTrialReminder: async () => void calls.push("reminder"),
        notifyTrialWhatsapp: async () => {
          throw new Error("Make non raggiungibile");
        },
      },
      NOW
    );
    expect(result).toEqual({ ok: true });
    expect(calls.sort()).toEqual(["confirmation", "reminder"]);
  });
```

- [ ] **Step 2: Verifica che falliscano**

Run: `cd functions && npx jest src/__tests__/enrollmentHandlers.test.ts`
Expected: FAIL in compilazione con `Object literal may only specify known properties, and 'notifyTrialWhatsapp' does not exist in type 'EnrollmentDeps'`

- [ ] **Step 3: Estendi `EnrollmentDeps`**

In `functions/src/enrollment/enrollment.ts`:

```ts
/** Notifiche best-effort, iniettabili (no-op nei test). */
export interface EnrollmentDeps {
  notifyTrialReminder?: (userId: string, courseId: string) => Promise<void>;
  notifyTrialConfirmation?: (userId: string, courseId: string) => Promise<void>;
  /** WhatsApp di conferma via webhook Make (solo con WHATSAPP_DEMO_MODE=live). */
  notifyTrialWhatsapp?: (userId: string, courseId: string) => Promise<void>;
  notifyWaitlist?: (courseId: string) => Promise<void>;
}
```

- [ ] **Step 4: Aggiungi la notifica al blocco `if (isTrialUser)`**

Sostituisci il blocco dopo la transazione:

```ts
  if (isTrialUser) {
    // Best-effort e in parallelo: conferma immediata + promemoria schedulato.
    // Un errore di notifica non deve far fallire un'iscrizione già committata.
    await Promise.all([
      deps.notifyTrialConfirmation
        ? deps.notifyTrialConfirmation(targetUserId, courseId).catch(() => undefined)
        : Promise.resolve(),
      deps.notifyTrialReminder
        ? deps.notifyTrialReminder(targetUserId, courseId).catch(() => undefined)
        : Promise.resolve(),
    ]);
  }
```

con:

```ts
  if (isTrialUser) {
    // Best-effort e in parallelo: email di conferma, promemoria schedulato e
    // WhatsApp di conferma. Un errore di notifica non deve far fallire
    // un'iscrizione già committata.
    await Promise.all([
      deps.notifyTrialConfirmation
        ? deps.notifyTrialConfirmation(targetUserId, courseId).catch(() => undefined)
        : Promise.resolve(),
      deps.notifyTrialReminder
        ? deps.notifyTrialReminder(targetUserId, courseId).catch(() => undefined)
        : Promise.resolve(),
      deps.notifyTrialWhatsapp
        ? deps.notifyTrialWhatsapp(targetUserId, courseId).catch(() => undefined)
        : Promise.resolve(),
    ]);
  }
```

- [ ] **Step 5: Verifica che passino, insieme ai test esistenti**

Run: `cd functions && npx jest src/__tests__/enrollmentHandlers.test.ts src/__tests__/trial.test.ts`
Expected: PASS, compresi tutti i test preesistenti

- [ ] **Step 6: Aggiorna `README_ISCRIZIONI.md`**

In `lib/api/courses/README_ISCRIZIONI.md`, riga 18 (riga `subscribeToCourse` della tabella), sostituisci la parte finale `, promemoria prova |` con:

```markdown
, notifiche prova (email di conferma, promemoria, WhatsApp di conferma via Make) |
```

Poi, subito dopo il paragrafo che termina con `anche se \`tipologiaIscrizione\` legacy è rimasta \`ABBONAMENTO_PROVA\`.` (righe 142-145), aggiungi:

```markdown
- il WhatsApp di conferma (webhook Make) parte dalla stessa decisione
  `isTrialUser` (`functions/src/enrollment/trial.ts`), solo con
  `WHATSAPP_DEMO_MODE=live`; il promemoria WhatsApp della sera prima è un cron
  separato (`functions/src/whatsapp/reminders.ts`) che riusa lo stesso predicato.
```

- [ ] **Step 7: Commit**

```bash
git add functions/src/enrollment/enrollment.ts functions/src/__tests__/enrollmentHandlers.test.ts lib/api/courses/README_ISCRIZIONI.md
git commit -m "feat(enrollment): notifica WhatsApp di conferma per gli utenti di prova"
```

---

### Task 11: Wiring in `index.ts`, gate `WHATSAPP_DEMO_MODE` e modalità della produzione

**Files:**
- Modify: `functions/src/index.ts` (import in testa; blocco subito dopo `const oneSignalApiKey = defineSecret(…)`; export `subscribeToCourse`; due export in fondo)
- Modify: `.gitignore` (eccezione per la sola configurazione produzione)
- Create: `functions/.env.fit-rope-app-1f575`
- Test: `functions/src/__tests__/indexExports.test.ts`

**Interfaces:**
- Consumes: `whatsappDemoMode` (Task 4); `postToMake` (Task 5); `WhatsappDeps`, `notifyDemoLessonBooked` (Task 7); `runDemoLessonReminders` (Task 8); `sendTestDemoLessonWebhookHandler` (Task 9); `EnrollmentDeps.notifyTrialWhatsapp` (Task 10)
- Produces: export condizionali `sendTestDemoLessonWebhook` (callable, modalità `test|live`) e `sendDemoLessonWhatsappReminders` (onSchedule, modalità `live`); secret Make legati a `subscribeToCourse` solo in modalità `live`

- [ ] **Step 1: Scrivi i test che falliscono**

In `functions/src/__tests__/indexExports.test.ts`:

1. Aggiungi i due campi al tipo `IndexModule`:

```ts
type IndexModule = {
  sendTestCertificateEmail: unknown;
  certificateEmailsDaily: unknown;
  sendOneSignalNotification: unknown;
  checkEmailAvailability: unknown;
  setManagedUserEmail: unknown;
  subscribeToCourse: unknown;
  courseIcs: unknown;
  firestoreBackupDaily: unknown;
  firestoreBackupDailyCheck: unknown;
  sendTestDemoLessonWebhook: unknown;
  sendDemoLessonWhatsappReminders: unknown;
};
```

2. Aggiungi in fondo al file:

```ts
/** Nomi dei secret legati a una function (letti dal manifest che usa la CLI). */
function secretKeys(fn: unknown): string[] {
  const endpoint = (
    fn as { __endpoint?: { secretEnvironmentVariables?: Array<{ key: string }> } }
  ).__endpoint;
  return (endpoint?.secretEnvironmentVariables ?? []).map((s) => s.key).sort();
}

describe("gate WHATSAPP_DEMO_MODE (export condizionale in index.ts)", () => {
  const saved = {
    mode: process.env.WHATSAPP_DEMO_MODE,
    appEnv: process.env.APP_ENV,
    emulator: process.env.FUNCTIONS_EMULATOR,
  };

  beforeEach(() => {
    delete process.env.APP_ENV;
    delete process.env.FUNCTIONS_EMULATOR;
  });

  afterEach(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("WHATSAPP_DEMO_MODE", saved.mode);
    restore("APP_ENV", saved.appEnv);
    restore("FUNCTIONS_EMULATOR", saved.emulator);
  });

  test("off (default): nessuna function WhatsApp, subscribeToCourse senza secret Make", () => {
    delete process.env.WHATSAPP_DEMO_MODE;
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeUndefined();
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
    // La prima asserzione valida anche il selettore: se __endpoint cambiasse
    // forma, fallirebbe qui invece di passare in silenzio.
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("valore sconosciuto: come off", () => {
    process.env.WHATSAPP_DEMO_MODE = "si";
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeUndefined();
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
  });

  test("test: solo la callable di prova, con i secret Make", () => {
    process.env.WHATSAPP_DEMO_MODE = "test";
    const mod = loadIndex();
    expect(secretKeys(mod.sendTestDemoLessonWebhook)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
    ]);
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("live: callable di prova, cron e secret Make anche su subscribeToCourse", () => {
    process.env.WHATSAPP_DEMO_MODE = "live";
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeDefined();
    expect(secretKeys(mod.sendDemoLessonWhatsappReminders)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
    ]);
    expect(secretKeys(mod.subscribeToCourse)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
      "ONESIGNAL_REST_API_KEY",
    ]);
  });
});
```

- [ ] **Step 2: Verifica che falliscano**

Run: `cd functions && npx jest src/__tests__/indexExports.test.ts`
Expected: FAIL. Nei test `test` e `live` `sendTestDemoLessonWebhook` risulta undefined. Il test `off` deve già passare: se fallisce sull'asserzione `ONESIGNAL_REST_API_KEY`, il selettore `__endpoint.secretEnvironmentVariables` non corrisponde a firebase-functions 7.3.2. In quel caso ispeziona la forma reale con un `console.log(JSON.stringify((mod.subscribeToCourse as { __endpoint?: unknown }).__endpoint))` temporaneo nel test e correggi `secretKeys` prima di proseguire.

- [ ] **Step 3: Aggiungi gli import in `index.ts`**

Sotto `import { isStagingCloneMode, stagingCloneGuarded } from "./stagingCloneGuard";`:

```ts
import { whatsappDemoMode } from "./whatsapp/environment";
import { postToMake } from "./whatsapp/makeClient";
import { WhatsappDeps, notifyDemoLessonBooked } from "./whatsapp/demoLesson";
import { runDemoLessonReminders } from "./whatsapp/reminders";
import { sendTestDemoLessonWebhookHandler } from "./whatsapp/testWebhook";
```

- [ ] **Step 4: Aggiungi il gate subito dopo `const oneSignalApiKey = defineSecret("ONESIGNAL_REST_API_KEY");`**

```ts
// ──────────────────────────────────────────────
//  WhatsApp lezioni demo (webhook Make)
// ──────────────────────────────────────────────
//
// WHATSAPP_DEMO_MODE, in `.env.<projectId>`, viene letta in DISCOVERY come i
// gate dei certificati:
//   off (default) → nessuna function e nessun secret dichiarato;
//   test          → solo la callable di prova (Admin), per verificare lo scenario Make;
//   live          → + WhatsApp di conferma in subscribeToCourse + cron delle 19:00.
// Mergiare significa deployare: è questo gate, e non la scelta di cosa
// deployare, a tenere spento il cron finché scenario Make e template Meta non
// sono pronti. I secret vengono dichiarati solo se servono: su staging, di norma
// in modalità off, il deploy non deve chiedere secret che lì non esistono.
const whatsappMode = whatsappDemoMode(process.env);
const makeSecret =
  whatsappMode === "off"
    ? null
    : {
        url: defineSecret("MAKE_WEBHOOK_URL"),
        key: defineSecret("MAKE_WEBHOOK_KEY"),
      };
const makeSecrets = makeSecret ? [makeSecret.url, makeSecret.key] : [];

function makeWhatsappDeps(): WhatsappDeps {
  if (!makeSecret) {
    throw new HttpsError(
      "failed-precondition",
      "WhatsApp demo disattivato (WHATSAPP_DEMO_MODE=off)",
    );
  }
  return {
    db: admin.firestore(),
    webhookUrl: makeSecret.url.value(),
    apiKey: makeSecret.key.value(),
    post: postToMake,
    nowMillis: Date.now(),
    env: process.env,
  };
}
```

- [ ] **Step 5: Sostituisci l'export `subscribeToCourse`**

```ts
export const subscribeToCourse = onCall(
  {
    region: "europe-west8",
    cors: true,
    secrets:
      whatsappMode === "live" ? [oneSignalApiKey, ...makeSecrets] : [oneSignalApiKey],
  },
  stagingCloneGuarded((request) =>
    subscribeToCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
      {
        notifyTrialReminder: (userId, courseId) =>
          scheduleTrialReminder(
            admin.firestore(),
            oneSignalApiKey.value(),
            userId,
            courseId,
            Date.now(),
          ),
        notifyTrialConfirmation: (userId, courseId) =>
          sendTrialEnrollmentConfirmation(
            admin.firestore(),
            oneSignalApiKey.value(),
            userId,
            courseId,
            Date.now(),
          ),
        // async: anche un errore sincrono (es. secret non leggibile) diventa un
        // rifiuto, che subscribeToCourseHandler ignora come le altre notifiche.
        // Senza async farebbe fallire un'iscrizione già committata.
        ...(whatsappMode === "live"
          ? {
              notifyTrialWhatsapp: async (userId: string, courseId: string) => {
                await notifyDemoLessonBooked(makeWhatsappDeps(), userId, courseId);
              },
            }
          : {}),
      },
    )),
);
```

Lascia invariato il commento JSDoc sopra l'export.

- [ ] **Step 6: Aggiungi i due export in fondo a `index.ts`**

```ts
/**
 * WhatsApp di prova verso il numero indicato (DebugEmailPage, kDebugMode).
 * Solo Admin. Esiste con WHATSAPP_DEMO_MODE=test|live.
 * Payload: { numeroTelefono: string, kind?: "booked"|"reminder", nome?, corso?, giorno?, orario? }
 */
export const sendTestDemoLessonWebhook =
  whatsappMode === "off"
    ? undefined
    : onCall(
        { secrets: makeSecrets, region: "europe-west8", cors: true },
        stagingCloneGuarded((request) =>
          sendTestDemoLessonWebhookHandler(
            { auth: request.auth ?? null, data: request.data },
            makeWhatsappDeps(),
          )),
      );

/**
 * Promemoria WhatsApp delle lezioni di prova di domani, ogni sera alle 19:00
 * Europe/Rome. Esiste solo con WHATSAPP_DEMO_MODE=live. La condizione viene
 * rivalutata a runtime come guardia difensiva, come per i certificati.
 */
export const sendDemoLessonWhatsappReminders =
  whatsappMode === "live"
    ? onSchedule(
        {
          schedule: "0 19 * * *",
          timeZone: "Europe/Rome",
          region: "europe-west8",
          secrets: makeSecrets,
          timeoutSeconds: 540,
          maxInstances: 1,
          retryCount: 3,
          minBackoffSeconds: 30,
        },
        async (event) => {
          if (whatsappDemoMode(process.env) !== "live" || isStagingCloneMode()) {
            logger.warn(
              "sendDemoLessonWhatsappReminders fuori da WHATSAPP_DEMO_MODE=live o su clone staging: no-op",
            );
            return;
          }
          await runDemoLessonReminders(makeWhatsappDeps(), {
            scheduledAtMillis: new Date(event.scheduleTime).getTime(),
            deadlineMillis: Date.now() + 480_000,
          });
        },
      )
    : undefined;
```

- [ ] **Step 7: Crea la configurazione della produzione**

`functions/.env.fit-rope-app-1f575`:

```dotenv
# Configurazione NON segreta delle Functions in produzione (fit-rope-app-1f575).
# La CLI Firebase carica questo file prima della discovery degli export.
# NON aggiungere APP_ENV: i gate certificati e backup in index.ts dipendono
# dalla sua assenza in produzione.
#
# WhatsApp lezioni demo (webhook Make): off | test | live — vedi CLAUDE.md.
# `test` tiene in produzione la callable di prova già deployata; passare a
# `live` solo dopo scenario Make configurato e template Meta approvati.
WHATSAPP_DEMO_MODE=test
```

In `.gitignore`, subito dopo `!/functions/.env.staging.example`, aggiungi **solo**:

```gitignore
!/functions/.env.fit-rope-app-1f575
```

L'eccezione non si estende a `.env.fit-rope-staging` né ad altri file di ambiente. Verifica con `git check-ignore -v --no-index functions/.env.fit-rope-app-1f575`: non deve produrre una regola di esclusione finale; la verifica decisiva è che il file compaia nell'indice dopo `git add` e nel diff della PR.

- [ ] **Step 8: Verifica build, export e suite completa**

Run: `cd functions && npm run build && npx jest src/__tests__/indexExports.test.ts && npm test`
Expected: build senza errori; `indexExports` PASS, compresi i test preesistenti sui certificati; suite completa PASS. Aggiungi in `indexExports.test.ts` un'asserzione sui parametri del cron (`timeoutSeconds: 540`, `maxInstances: 1`, retry abilitato) usando il manifest effettivo di firebase-functions.

- [ ] **Step 9: Commit**

```bash
git add .gitignore functions/src/index.ts functions/src/__tests__/indexExports.test.ts functions/.env.fit-rope-app-1f575
git ls-files --error-unmatch functions/.env.fit-rope-app-1f575
git commit -m "feat(functions): gate WHATSAPP_DEMO_MODE, conferma in subscribeToCourse e cron WhatsApp"
```

---

### Task 12: Sezione WhatsApp nella pagina di debug

**Files:**
- Modify: `lib/services/notification_service.dart` (nuova funzione in fondo)
- Modify: `lib/pages/protected/debug_email_page.dart` (stato, `dispose`, `_lookupUser`, nuovo metodo, nuova sezione in fondo al `build`)

**Interfaces:**
- Consumes: la callable `sendTestDemoLessonWebhook` (Task 11), che risponde `{ ok, status, payload }`
- Produces: `Future<({bool ok, int status, Map<String, String> payload})> sendTestDemoLessonWebhook({required String numeroTelefono, String kind = 'booked', String? nome, String? corso, String? giorno, String? orario})`

Non esistono test Flutter per la pagina di debug né per il service (vedi `test/`), e non se ne aggiungono qui. La verifica è `flutter analyze` + `dart format` + prova manuale al Task 14.

- [ ] **Step 1: Aggiungi la funzione al service**

In fondo a `lib/services/notification_service.dart` (`SimulationSession`, `FirebaseFunctions` e `kDebugMode` sono già importati):

```dart
/// Manda un payload di prova al webhook Make verso [numeroTelefono] e
/// restituisce l'esito e il body effettivamente inviato, così la pagina di
/// debug può mostrarlo. Lato server richiede il ruolo Admin e
/// WHATSAPP_DEMO_MODE=test|live. [kind] vale `'booked'` (tipo `conferma`) o
/// `'reminder'` (tipo `promemoria`); i campi vuoti ricadono su default.
Future<({bool ok, int status, Map<String, String> payload})>
    sendTestDemoLessonWebhook({
  required String numeroTelefono,
  String kind = 'booked',
  String? nome,
  String? corso,
  String? giorno,
  String? orario,
}) async {
  SimulationSession.assertNotSimulating('sendTestDemoLessonWebhook');
  assert(kDebugMode);
  debugPrint('📲 [Make] test webhook — kind: $kind');
  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('sendTestDemoLessonWebhook');
    final result = await callable.call({
      'numeroTelefono': numeroTelefono,
      'kind': kind,
      'nome': nome ?? '',
      'corso': corso ?? '',
      'giorno': giorno ?? '',
      'orario': orario ?? '',
    });
    debugPrint('📲 [Make] test webhook — RESPONSE: ${result.data}');
    final data = (result.data as Map<Object?, Object?>?) ?? const {};
    final payload = (data['payload'] as Map<Object?, Object?>?) ?? const {};
    return (
      ok: data['ok'] == true,
      status: (data['status'] as num?)?.toInt() ?? 0,
      payload: payload.map((key, value) => MapEntry('$key', '$value')),
    );
  } on FirebaseFunctionsException catch (e) {
    debugPrint('📲 [Make] test webhook — ERROR ${e.code}: ${e.message}');
    rethrow;
  } catch (e) {
    debugPrint('📲 [Make] test webhook — ERROR: $e');
    rethrow;
  }
}
```

- [ ] **Step 2: Aggiungi lo stato alla pagina**

In `lib/pages/protected/debug_email_page.dart`, subito dopo `final _salaCtrl = TextEditingController(text: 'Sala 1');`:

```dart
  final _phoneCtrl = TextEditingController();
  final _whatsappNameCtrl = TextEditingController();
  // Il WhatsApp usa un formato data diverso dalle email ("28 aprile 2026" contro
  // "Lunedì 28 Aprile 2025"), quindi ha un campo suo.
  final _whatsappDayCtrl = TextEditingController(text: '28 aprile 2026');
```

Subito dopo `bool _sendingCertExpiry = false;`:

```dart
  bool _sendingWhatsapp = false;
  Map<String, String>? _lastWhatsappPayload;
```

In `dispose()`, subito dopo `_salaCtrl.dispose();`:

```dart
    _phoneCtrl.dispose();
    _whatsappNameCtrl.dispose();
    _whatsappDayCtrl.dispose();
```

- [ ] **Step 3: Precompila numero e nome completo nel lookup**

In `_lookupUser`, sostituisci:

```dart
        final name = data['name'] as String? ?? '';
        setState(() {
          _resolvedUid = uid;
          if (name.isNotEmpty) _firstNameCtrl.text = name;
        });
```

con:

```dart
        final name = data['name'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final phone = data['numeroTelefono'] as String? ?? '';
        setState(() {
          _resolvedUid = uid;
          if (name.isNotEmpty) _firstNameCtrl.text = name;
          // Il WhatsApp usa nome e cognome, come il payload reale.
          final fullName = '$name $lastName'.trim();
          if (fullName.isNotEmpty) _whatsappNameCtrl.text = fullName;
          if (phone.isNotEmpty) _phoneCtrl.text = phone;
        });
```

- [ ] **Step 4: Aggiungi il metodo di invio**

Subito prima di `  @override\n  Widget build(BuildContext context) {`:

```dart
  /// WhatsApp di prova via webhook Make. Non usa `_resolvedUid`: il
  /// destinatario è il numero digitato, così i template si provano sul
  /// proprio telefono.
  Future<void> _sendWhatsappTest({required String kind}) async {
    if (SimulationGuard.blockIfSimulating(context)) return;
    final numero = _phoneCtrl.text.trim();
    if (numero.isEmpty) return;
    setState(() {
      _sendingWhatsapp = true;
      _lastWhatsappPayload = null;
    });
    try {
      final result = await sendTestDemoLessonWebhook(
        numeroTelefono: numero,
        kind: kind,
        nome: _whatsappNameCtrl.text,
        corso: _courseNameCtrl.text,
        giorno: _whatsappDayCtrl.text,
        orario: _courseTimeCtrl.text,
      );
      if (mounted) {
        setState(() => _lastWhatsappPayload = result.payload);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.ok
                ? 'Webhook Make chiamato (tipo: ${result.payload['tipo']})'
                : 'Make ha risposto con status ${result.status}'),
            backgroundColor: result.ok ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingWhatsapp = false);
    }
  }

```

- [ ] **Step 5: Aggiungi la sezione in fondo al `build`**

Subito dopo il blocco del bottone `'Certificato — scadenza oggi'`, che termina con:

```dart
                label: const Text('Certificato — scadenza oggi'),
              ),
            ),
```

e prima del `],` che chiude la `Column`, inserisci:

```dart
            const SizedBox(height: 32),

            // --- WhatsApp (webhook Make) ---
            const Text(
              'WhatsApp (webhook Make)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo Admin, con WHATSAPP_DEMO_MODE=test o live. Usa anche '
              '"Nome corso" e "Orario" qui sopra; i campi vuoti ricadono su '
              'un default lato Cloud Function.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numero di telefono',
                border: OutlineInputBorder(),
                helperText: 'Destinatario del messaggio di prova (es. 3331234567)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whatsappNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome e cognome',
                border: OutlineInputBorder(),
                helperText: 'Campo "nome" del body',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whatsappDayCtrl,
              decoration: const InputDecoration(
                labelText: 'Giorno',
                border: OutlineInputBorder(),
                helperText: 'Formato WhatsApp: "28 aprile 2026" (diverso dalla Data delle email)',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: !_sendingWhatsapp
                    ? () => _sendWhatsappTest(kind: 'booked')
                    : null,
                icon: _sendingWhatsapp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('WhatsApp — conferma prenotazione'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: !_sendingWhatsapp
                    ? () => _sendWhatsappTest(kind: 'reminder')
                    : null,
                icon: _sendingWhatsapp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.alarm_on_outlined),
                label: const Text('WhatsApp — promemoria lezione'),
              ),
            ),
            if (_lastWhatsappPayload != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Body inviato a Make',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ..._lastWhatsappPayload!.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
```

- [ ] **Step 6: Formatta e verifica**

Run:

```bash
flutter pub get
dart format lib/services/notification_service.dart lib/pages/protected/debug_email_page.dart
flutter analyze --no-fatal-infos
dart format --set-exit-if-changed .
flutter test
```

Expected: nessun errore di analyze; nessun file riformattato dall'ultimo `dart format`; tutti i test PASS

- [ ] **Step 7: Commit**

```bash
git add lib/services/notification_service.dart lib/pages/protected/debug_email_page.dart
git commit -m "feat(debug): sezione WhatsApp nella pagina di debug"
```

---

### Task 13: Documentazione

**Files:**
- Modify: `CLAUDE.md`, `agents.md`, `functions/.env.staging.example`

**Interfaces:**
- Consumes: i nomi definiti nei task precedenti
- Produces: documentazione allineata al codice

- [ ] **Step 1: Nuova sezione in `CLAUDE.md`**

Inserisci subito prima di `## Struttura rapida` (il blocco usa quattro backtick perché contiene un blocco `bash`):

````markdown
### WhatsApp lezioni demo (webhook Make)

- Il messaggio **non** lo manda l'app: un `POST` verso un Custom webhook Make fa partire un template WhatsApp approvato da Meta. Il testo si modifica nello scenario Make, senza deploy.
- Codice in `functions/src/whatsapp/`, un modulo per responsabilità: `phone.ts` (E.164), `format.ts` (date di Roma, riusa `romeParts` di `notify.ts`), `payload.ts` (body), `environment.ts` (gate), `makeClient.ts` (unica chiamata HTTP), `sendLog.ts` (registro invii), `demoLesson.ts` (regole destinatario e conferma), `reminders.ts` (cron), `testWebhook.ts` (callable di prova).
- Due eventi su un solo webhook, distinti dal campo `tipo`:
  - `conferma` — `EnrollmentDeps.notifyTrialWhatsapp` in `subscribeToCourseHandler`, nel blocco `if (isTrialUser)` accanto all'email di conferma e al promemoria;
  - `promemoria` — cron `sendDemoLessonWhatsappReminders`, `0 19 * * *` Europe/Rome, per le lezioni del giorno dopo.
- **"Utente di prova" è un solo predicato**, `isTrialUser` in `functions/src/enrollment/trial.ts`, usato sia dall'iscrizione sia dal cron. Non filtrare mai su `tipologiaIscrizione` da sola: chi è stato convertito al multi-abbonamento può averla ancora a `ABBONAMENTO_PROVA`.
- Il cron usa `event.scheduleTime` per scegliere i corsi del giorno dopo anche quando Cloud Scheduler ritenta l'evento. Legge gli utenti con `array-contains-any` a blocchi da 30, filtra in memoria e avvia al massimo 10 invii concorrenti. A 480 secondi ferma l'avvio di nuovi invii e fa ritentare il job; timeout della function 540 secondi. Un solo filtro Firestore per query, quindi nessun indice composito.
- **Gate `WHATSAPP_DEMO_MODE`** in `.env.<projectId>`, letto in discovery: `off` (default: nessuna function, nessun secret dichiarato), `test` (solo `sendTestDemoLessonWebhook`), `live` (+ conferma + cron). Mergiare significa deployare: il cron resta spento grazie a questo gate. La produzione è configurata in `functions/.env.fit-rope-app-1f575`, file tracciato grazie all'eccezione specifica in `.gitignore`. Su staging la modalità è `off`, a meno che `staging.yml` non la scriva; accenderla lì richiede i secret nel progetto `fit-rope-staging` e `STAGING_WHATSAPP_ALLOWLIST`, perché staging può contenere numeri reali clonati da produzione.
- **Il body è un contratto con lo scenario Make**: `{tipo, nome, numero_di_telefono, corso, giorno, orario}`, tutte stringhe non vuote (`giorno` = `15 ottobre 2026`, `orario` = `18:00`). Make impara lo schema dal primo payload: aggiungere o rinominare una chiave richiede "Redetermine data structure" sul webhook. I parametri dei template non ammettono valori vuoti, newline, tab né 4+ spazi: ci pensa `sanitizeTemplateParam`.
- La chiave di autenticazione va nell'**header `Demo-Reminder`**, non nel body; nello scenario serve "Get request headers". URL e chiave sono esclusi da ogni log (si logga solo l'host).
- Secret (l'URL del webhook **è** una credenziale):

```bash
firebase functions:secrets:set MAKE_WEBHOOK_URL --project prod
firebase functions:secrets:set MAKE_WEBHOOK_KEY --project prod
firebase functions:log --only sendDemoLessonWhatsappReminders --project prod
```

- **Idempotenza**: ogni invio è registrato in `demoLessonWebhookLog/{kind}_{userId}_{courseId}` (identificativi, istante ed esito; nessun dato personale). Il claim si crea con `create()` *prima* della POST e resta persistente. Solo `ok: true` prova che Make ha accettato la conferma e può sopprimere il promemoria nello stesso giorno di Roma. `pending`/`unknown` dopo timeout, rete, 5xx o crash non vengono reinviati automaticamente: verifica in Make prima di un eventuale intervento manuale. Solo HTTP 429 ha due nuovi tentativi nello stesso run; gli altri 4xx sono `rejected`.
- `postToMake` **non lancia mai**, non deserializza la risposta (Make risponde `Accepted` in testo) e ha un `AbortSignal.timeout`. **Gli errori a valle del webhook non tornano indietro**: numero non su WhatsApp, template non approvato, credito esaurito danno comunque `200`. Attiva le notifiche di errore dello scenario in Make.
- `sendTestDemoLessonWebhook` è **solo Admin**: una callable è raggiungibile via HTTP da qualunque utente autenticato, e ogni WhatsApp è reale e a pagamento. In `kDebugMode` la `DebugEmailPage` ha una sezione WhatsApp che la usa; il campo *Giorno* ha un formato diverso dalla *Data* delle email.
````

- [ ] **Step 2: TODO in `CLAUDE.md`**

In fondo alla lista `## TODO / Da aggiornare` aggiungi:

```markdown
- **Promemoria prova OneSignal non annullabile**: `scheduleTrialReminder` (`functions/src/enrollment/notify.ts`) gira server-side ma schedula email e push con `send_after` al momento dell'iscrizione. Se l'utente si disiscrive, se il corso viene cancellato o spostato, o se `reminderEnabled` viene disattivato dopo, il messaggio parte comunque (il notification id non viene salvato). Ora che `sendDemoLessonWhatsappReminders` seleziona già i destinatari la sera prima, email e push possono spostarsi su quel cron con un invio immediato via `postToOneSignal`, senza `send_after`.
```

- [ ] **Step 3: `agents.md`**

Nella lista `### Collezioni Firestore` aggiungi:

```markdown
- `demoLessonWebhookLog` - registro degli invii WhatsApp (webhook Make): un documento per `{kind}_{userId}_{courseId}`, con identificativi, istante ed esito, senza dati personali; scrittura solo server
```

Nella tabella di `### Casi d'uso`, subito dopo le due righe `Iscrizione utente \`ABBONAMENTO_PROVA\``, aggiungi:

```markdown
| Iscrizione di un utente di prova (`isTrialUser`), con `WHATSAPP_DEMO_MODE=live` | Cloud Function `subscribeToCourse` → `functions/src/whatsapp/demoLesson.ts:notifyDemoLessonBooked` | Immediato — WhatsApp `conferma` via webhook Make |
| Sera prima della lezione, con `WHATSAPP_DEMO_MODE=live` | Cron `sendDemoLessonWhatsappReminders` → `functions/src/whatsapp/reminders.ts` | 19:00 Europe/Rome — WhatsApp `promemoria` via webhook Make, saltato se la conferma è partita lo stesso giorno |
```

Subito prima di `### Cloud Function` aggiungi:

```markdown
### WhatsApp lezioni demo (webhook Make)

- Moduli in `functions/src/whatsapp/`; il predicato "utente di prova" è `functions/src/enrollment/trial.ts`, condiviso con l'iscrizione.
- Gate `WHATSAPP_DEMO_MODE` (`off`/`test`/`live`) in `.env.<projectId>`, letto in discovery. Produzione: `functions/.env.fit-rope-app-1f575`. Staging: `off` salvo configurazione esplicita con `STAGING_WHATSAPP_ALLOWLIST`.
- La configurazione produzione è tracciata grazie a un'eccezione specifica in `.gitignore`. Il cron usa `event.scheduleTime` nei retry e un massimo di 10 invii concorrenti; i claim incerti restano nel registro per verifica in Make, senza reinvio automatico.
- Secret `MAKE_WEBHOOK_URL`, `MAKE_WEBHOOK_KEY`; chiave nell'header `Demo-Reminder`.
- Dettagli operativi e trappole in `CLAUDE.md`, sezione "WhatsApp lezioni demo".
```

- [ ] **Step 4: `functions/.env.staging.example`**

Aggiungi in fondo:

```dotenv
# WhatsApp lezioni demo (webhook Make): off (default) | test | live.
# Su staging lasciare off, oppure creare i secret MAKE_WEBHOOK_URL e
# MAKE_WEBHOOK_KEY nel progetto fit-rope-staging e compilare l'allowlist:
# staging può contenere numeri reali clonati dalla produzione.
# WHATSAPP_DEMO_MODE=off
# STAGING_WHATSAPP_ALLOWLIST=+393331234567
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md agents.md functions/.env.staging.example
git commit -m "docs: integrazione WhatsApp lezioni demo via webhook Make"
```

---

### Task 14: Verifica finale e PR verso `develop`

**Files:**
- Nessuna modifica al codice

**Interfaces:**
- Consumes: tutti i task precedenti
- Produces: PR aperta su `fgrotta/fitrope_app` con base `develop`

- [ ] **Step 1: Suite complete**

```bash
cd functions && npm run build && npm test
cd .. && flutter test && flutter analyze --no-fatal-infos && dart format --set-exit-if-changed .
```

Expected: tutto PASS, nessun file da riformattare.

- [ ] **Step 2: Integration test sull'emulatore (se l'ambiente ha Java 21 e firebase-tools)**

```bash
cd functions && printf "ONESIGNAL_REST_API_KEY=emulator-dummy-key\n" > .secret.local && npm run test:integration
```

Expected: PASS. L'emulatore gira con `--project demo-fitrope`, dove `WHATSAPP_DEMO_MODE` non è impostata: la modalità è `off`, quindi questo verifica che l'iscrizione reale non sia stata rotta. Se l'ambiente non ha Java, salta lo step: lo stesso job gira in CI (`functions-integration`). `.secret.local` è ignorato da git (`*.local`).

Prima della PR verifica inoltre i test Jest dei Task 6–8: in particolare nessun secondo POST dopo timeout/5xx, retry limitato di HTTP 429, al massimo 10 invii concorrenti e ripresa del batch con lo stesso `scheduledAtMillis` oltre la mezzanotte. Il test di integrazione sopra gira in modalità `off` e non sostituisce questi casi.

- [ ] **Step 3: Revisione di dominio**

Chiedi all'agente `fitrope-enrollment-reviewer` di rivedere il diff di `functions/src/enrollment/` (Task 1 e 10) rispetto a `origin/develop`, con particolare attenzione al fatto che `isTrialUser` non abbia cambiato comportamento.

- [ ] **Step 4: Controlla cosa stai per pubblicare**

```bash
git status --short
git log --oneline origin/develop..HEAD
git diff --stat origin/develop...HEAD
git ls-files --error-unmatch functions/.env.fit-rope-app-1f575
git diff origin/develop...HEAD --name-only | grep -Fx functions/.env.fit-rope-app-1f575
```

Expected: nessun file untracked da includere (in particolare **non** `functions/.env.fit-rope-staging`); 14 commit (uno per task); diff limitato a `functions/src/whatsapp/`, `functions/src/enrollment/{trial,enrollment}.ts`, `functions/src/index.ts`, `.gitignore`, i test, `functions/.env.fit-rope-app-1f575`, i due file Dart e la documentazione. I due ultimi comandi devono trovare la configurazione produzione nel commit e nel diff.

- [ ] **Step 5: Push e PR**

```bash
git push -u origin fgrotta/whatsapp-demo-develop
gh pr create --repo fgrotta/fitrope_app --base develop \
  --title "WhatsApp lezioni demo via webhook Make (porting su develop)" \
  --body-file - <<'EOF'
## Cosa fa

Riporta su `develop` l'integrazione WhatsApp → webhook Make per le lezioni di prova, adattata all'architettura attuale. Il branch originale `fgrotta/make-whatsapp-webhook-demo` era nato da `main` v1.2.7 e non è integrabile.

- **Conferma** all'iscrizione: nuova notifica best-effort `EnrollmentDeps.notifyTrialWhatsapp` in `subscribeToCourseHandler`, accanto all'email di conferma e al promemoria.
- **Promemoria** la sera prima: cron `sendDemoLessonWhatsappReminders` (19:00 Europe/Rome).
- Predicato "utente di prova" estratto in `enrollment/trial.ts` e condiviso: il cron non scrive ai clienti convertiti che hanno ancora la tipologia legacy PROVA.
- Gate `WHATSAPP_DEMO_MODE` (`off`/`test`/`live`) in discovery; produzione in `test` tramite `functions/.env.fit-rope-app-1f575`; staging `off`.
- Configurazione produzione effettivamente tracciata; cron con ripresa del batch e invii limitati a 10 concorrenti.
- Esiti Make incerti persistono nel registro per verifica manuale: niente nuovo WhatsApp automatico dopo timeout, rete o 5xx.
- Callable di prova riservata agli Admin, e sezione WhatsApp nella pagina di debug.

## Da sapere prima del rilascio in produzione

- La produzione ha ancora `notifyDemoLessonBooked`, deployata dal vecchio branch e non più presente nel codice: il deploy non interattivo si ferma finché non viene rimossa.
- Anche `sendCertificateExpiryEmails` e `sendTestCertificateEmail` sono in produzione ma escluse dal codice di `develop` (PR #8): decisione separata.
- Il cron **non** si attiva con questo merge: serve passare `WHATSAPP_DEMO_MODE` a `live`, dopo aver configurato lo scenario Make e i template Meta.

## Test

- Unit Jest per ogni modulo `functions/src/whatsapp/`, per `trial.ts`, per la nuova dipendenza in `enrollmentHandlers.test.ts` e per il gate in `indexExports.test.ts`.
- `flutter test`, `flutter analyze --no-fatal-infos`, `dart format --set-exit-if-changed .`
EOF
```

Aggiungi in fondo al body le righe di attribuzione richieste dall'ambiente di esecuzione.

- [ ] **Step 6: Dopo il merge, verifica staging**

```bash
firebase functions:list --project fit-rope-staging | grep -iE "whatsapp|DemoLesson" || echo "nessuna function WhatsApp su staging: atteso con modalità off"
```

Expected: nessuna function WhatsApp su staging, e smoke test di `staging.yml` verde.

---

## Rilascio in produzione (fuori da questo piano: ogni punto richiede l'ok esplicito dell'utente)

1. **Prerequisiti fuori dal repo**: numero dedicato su WhatsApp Business Cloud API; due template **Utility** approvati da Meta (conferma prenotazione, promemoria appuntamento) con parametri `nome`, `corso`, `giorno`, `orario`; nello scenario Make "Get request headers" + filtro sull'header `Demo-Reminder`, "Redetermine data structure" e Router su `tipo`; notifiche di errore dello scenario attive.
2. **Sblocco del deploy di produzione**: prima del primo deploy che contiene questo lavoro va rimossa `notifyDemoLessonBooked`, che non esiste più nel codice e nessun client chiama:
   ```bash
   firebase functions:delete notifyDemoLessonBooked --region europe-west8 --project prod
   ```
   `sendCertificateExpiryEmails` e `sendTestCertificateEmail` bloccano allo stesso modo: la decisione è di prodotto, perché cancellarle ferma le email certificati che oggi partono ogni mattina.
3. **Verifica in modalità `test`**: dalla pagina di debug (utente Admin, build debug puntata alla produzione) manda conferma e promemoria al proprio numero. Controlla che Make riceva le 6 chiavi e l'header, e che il Router instradi su `tipo`.
4. **Go-live**: PR su `develop` che porta `functions/.env.fit-rope-app-1f575` a `WHATSAPP_DEMO_MODE=live`. Dopo il rilascio verifica che esista il job Scheduler (`gcloud scheduler jobs list --location europe-west8 --project fit-rope-app-1f575`) e controlla la prima esecuzione con `firebase functions:log --only sendDemoLessonWhatsappReminders --project prod`. Confronta i contatori `failed` con i documenti `demoLessonWebhookLog` in stato `pending`, `unknown` o `rejected`; per ciascun caso incerto verifica prima in Make se il webhook è stato accettato, poi decidi manualmente se inviare di nuovo. Non cancellare un claim incerto alla cieca.
5. **Pulizia**: cancella il branch `fgrotta/make-whatsapp-webhook-demo`, locale e su `origin`.

## Rischi aperti

- **La callable di prova oggi in produzione è aperta a tutti gli utenti loggati.** La `sendTestDemoLessonWebhook` deployata dal vecchio branch controlla solo il login: chiunque sia registrato può mandare WhatsApp a numeri arbitrari. È un rischio latente finché lo scenario Make non è collegato a WhatsApp. **Non collegare il modulo WhatsApp in Make prima che questo lavoro, che la limita agli Admin, sia in produzione.**
- Anche `notifyDemoLessonBooked`, oggi in produzione, non verifica che l'utente sia davvero iscritto al corso: un utente di prova potrebbe farsi mandare conferme per qualsiasi corso futuro, sul proprio numero. Anche questo è latente, e sparisce con il punto 2 del rilascio.
- Il workflow di deploy di produzione (`production-build.yml`) non era visibile su `origin` al 2026-09-25. Se scrivesse un proprio `.env.fit-rope-app-1f575`, come fa `staging.yml` per staging, sovrascriverebbe quello tracciato e la modalità tornerebbe `off`. In quel caso `sendTestDemoLessonWebhook` sparirebbe dal codice e bloccherebbe il deploy. Verificalo quando il workflow viene pubblicato.
- Da verificare in Make: cosa succede alle richieste che il webhook riceve a scenario spento. Se vengono accodate, riattivando lo scenario partirebbero tutte insieme, con giorni di ritardo.
- Con la policy anti-doppioni, un timeout o un crash può lasciare un claim `pending`/`unknown` anche quando il messaggio non è arrivato: resta da verificare manualmente in Make. Un HTTP `200 Accepted` prova solo che Make ha ricevuto il webhook, non che WhatsApp abbia consegnato il messaggio.
