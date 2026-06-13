# Sistema di Iscrizioni e Disiscrizione ai Corsi - FitRope

## Panoramica

Il sistema gestisce le iscrizioni ai corsi basandosi su due tipi principali di abbonamento:
- **Pacchetto Entrate**: Sistema a crediti con regole specifiche per i rimborsi
- **Abbonamenti Temporali**: Mensile, Trimestrale, Semestrale, Annuale con limiti settimanali

## Write-path server-side (da PR4)

Da PR4 **tutte le scritture** del dominio iscrizioni passano dalle Cloud Functions
(`europe-west8`, transazioni atomiche con Admin SDK). I file Dart in
`lib/api/courses/` mantengono le stesse firme ma sono **thin wrapper** delle
callable; il client non scrive più direttamente su corsi/utenti/abbonamenti:

| Callable | Handler | Cosa fa |
|---|---|---|
| `subscribeToCourse` | `functions/src/enrollment/enrollment.ts` | Eligibility (accesso tag/abbonamenti, crediti, limite settimanale per tipologia, scadenza), capienza, decremento `remainingEntries`/`entrateDisponibili` + snapshot, rimozione da waitlist, promemoria prova |
| `unsubscribeFromCourse` | idem | Self: finestre rimborso **8h** (ingressi) / **4h** (frequenza), ripristino credito, `entryLost` + `cancelledEnrollments`. **Admin/Trainer su altri (da PR5): rimborsa SEMPRE** (`confirmedNoRefund` ignorato, nessuna finestra, nessun tracking). Notifica waitlist |
| `joinWaitlist` / `leaveWaitlist` | idem | Port delle regole client (corso pieno, duplicati, pulizia incoerenze) |
| `assignSubscription` *(admin, da PR3)* | `assignSubscription.ts` | Crea doc `subscriptions` + snapshot, max 1 attivo per famiglia |
| `deleteCourse` *(SOLO Admin, da PR5)* | `admin.ts` | UNA transazione atomica: corsi FUTURI → rimborsa tutti gli iscritti (registro consumi, regola admin-rimborsa-sempre); corsi GIÀ INIZIATI (pulizia storico) → nessun rimborso, solo rimozione iscrizioni/waitlist. Niente email waitlist |
| `recountCourseSubscribed` *(SOLO Admin, da PR5)* | `admin.ts` | Ricalcola `subscribed` dalla fonte di verità (utenti con il corso in `courses[]`), in transazione |

La logica autoritativa è nei moduli puri (mirror di `getCourseState.dart` /
`CourseUnsubscribeHelper`): `eligibility.ts`, `refund.ts`, `courseTypes.ts`,
`plansCatalog.ts`, `subscription.ts`. **Se modifichi le regole qui o lì, tieni
allineati i due lati** (client = display/UX, server = enforcement).

Da PR6 l'enforcement è EFFETTIVO: `firestore.rules` (nel repo) nega ai client
le scritture sui campi del dominio iscrizioni (courses, waitlistCourses,
activeSubscriptions, enrollmentConsumption, cancelledEnrollments, subscribed,
waitlist, collezione subscriptions) e su `role`/crediti per i non-Admin —
le callable sono l'unica via di scrittura. Test: categoria D in
`functions/src/__integration__/firestoreRules.integration.test.ts`.

Garanzie aggiuntive del write-path server (oltre il porting 1:1):
- **Valutazione in transazione**: eligibility, capienza, già-iscritto e limite
  settimanale sono valutati sui dati letti **dentro** la transazione (il doc
  utente fresco serializza le richieste concorrenti dello stesso utente: il
  limite settimanale non è bypassabile con doppi tap/device paralleli).
- **Registro consumi per prenotazione** (`users.{uid}.enrollmentConsumption`,
  mappa `courseId → {kind, subscriptionId?}`): allo subscribe si registra ciò
  che è stato REALMENTE scalato; all'unsubscribe si ripristina QUELLA fonte.
  Così la transizione legacy→abbonamento non conia né brucia crediti (es.
  prenotazione fatta da legacy + abbonamento assegnato dopo → rimborso
  all'entrata legacy), e un force-subscribe che non ha scalato nulla (credito a
  zero) non genera mai un rimborso. Prenotazioni pre-registro: fallback alla
  risoluzione dal modello attuale. Ripristino con clamp al massimo del piano.
- **Snapshot stantio**: le voci di `activeSubscriptions` scadute rispetto ad
  adesso sono ESCLUSE dalla selezione del modello (server e client): un utente
  con soli abbonamenti scaduti torna al percorso legacy e i suoi crediti
  restano utilizzabili.
- **Gate CLOSED**: il server rifiuta iscrizioni a corsi già iniziati (il force
  admin può registrare presenze a posteriori); `joinWaitlist` rispetta
  `waitlistEnabled`.

Differenze deliberate rispetto al vecchio client (fix di bug, non regressioni):
- il vecchio `subscribeToCourse` client decrementava `entrateDisponibili` **per
  tutti** (anche abbonamenti temporali, andando in negativo); il server decrementa
  solo per i modelli a ingressi (PACCHETTO_ENTRATE/PROVA o abbonamenti ENTRIES);
- eligibility (crediti/limiti/accesso) ora è **enforceata** anche server-side
  (prima era garantita solo dalla UI via `getCourseState`);
- `forceUnsubscribeWithNoRefund` **fuori** finestra rimborsa comunque (non si può
  perdere credito quando il rimborso è dovuto);
- promemoria prova e notifiche waitlist partono dal server
  (`functions/src/enrollment/notify.ts`), con date in Europe/Rome; il promemoria
  prova NON parte per utenti già convertiti al multi-abbonamento (snapshot vivo),
  anche se `tipologiaIscrizione` legacy è rimasta `ABBONAMENTO_PROVA`.

Restano client-side (con scritture dirette Firestore) SOLO
`createCourse`/`updateCourse` (CRUD corso, non toccano iscrizioni;
`updateCourse` esclude già i campi server-owned `subscribed`/`waitlist` dal
payload; migrazione pianificata, vedi `// TODO(server-migration)`).

Da PR5 i flussi admin sono server-side e i caveat interim di PR4 sono risolti:
- `removeUserFromCourse` (l'alias legacy `forceUnsubscribeFromCourse` è stato
  rimosso: stessa operazione) → callable
  `unsubscribeFromCourse` (il server riconosce actor ≠ target e rimborsa
  SEMPRE, anche `remainingEntries` del nuovo modello via registro consumi;
  `confirmedNoRefund` è ignorato per le operazioni su altri utenti). Fix
  rispetto al legacy: il contatore `subscribed` ora viene decrementato anche
  dalla rimozione admin (prima no: era l'origine delle discrepanze) e niente
  crash con `entrateDisponibili` null.
- `deleteCourse` → callable atomica (prima era N+2 transazioni separate che
  inviavano email "posto disponibile" per un corso in cancellazione).
- "Correggi conteggio" → callable `recountCourseSubscribed` (il client non
  calcola/scrive più il valore).
- Il registro consumi ha retention 90 giorni (pruning opportunistico a ogni
  scrittura: le correzioni admin a posteriori restano possibili entro quella
  finestra).

## Logica per Pacchetto Entrate

### Iscrizione
- Decrementa `entrateDisponibili` di 1
- Aggiunge il corso alla lista `courses` dell'utente

### Disiscrizione
- **Più di 8 ore prima**: Credito completamente rimborsato
- **Entro 8 ore prima**: 
  - Richiede conferma utente tramite dialog
  - **NON** rimborsa il credito
  - L'utente perde definitivamente l'ingresso

### Funzioni Disponibili

#### 1. `unsubscribeToCourse(courseId, userId)`
- **Disiscrizione normale** con rimborso completo
- Usata solo quando il rimborso è consentito (> 8 ore)
- Rimborsa sempre il credito per i Pacchetti Entrate

#### 2. `forceUnsubscribeWithNoRefund(courseId, userId)`
- **Disiscrizione forzata** senza rimborso
- Usata quando l'utente conferma di voler perdere il credito
- Non incrementa mai `entrateDisponibili`

## Logica per Abbonamenti Temporali

### Iscrizione
- Controlla limite settimanale (`entrateSettimanali`)
- Verifica validità abbonamento (`fineIscrizione`)
- Non modifica `entrateDisponibili`

### Disiscrizione
- Sempre rimborsa il posto nel corso
- Non ha impatto sui crediti

## Gestione Admin

### Funzioni Admin (Sempre Rimborsano)
- `removeUserFromCourse(courseId, userId)` - Rimozione utente specifico
- `deleteCourse(courseId)` - Cancellazione corso completo (SOLO Admin)

**Importante**: Le funzioni admin **sempre** restituiscono il credito
(pacchetti legacy E `remainingEntries` del nuovo modello, via registro
consumi), indipendentemente dal tempo rimanente — ECCEZIONE: `deleteCourse`
di un corso GIÀ INIZIATO non rimborsa (i partecipanti hanno frequentato;
è la pulizia del calendario/storico).

## Flusso di Utilizzo per Pacchetto Entrate

### Scenario 1: Disiscrizione > 8 ore prima
```dart
await unsubscribeToCourse(courseId, userId);
// Credito rimborsato automaticamente
```

### Scenario 2: Disiscrizione ≤ 8 ore prima
```dart
// L'helper verifica automaticamente se serve conferma
final unsubscribeInfo = CourseUnsubscribeHelper.canUnsubscribe(course, user);

if (unsubscribeInfo['requiresConfirmation']) {
  // Mostra dialog di conferma all'utente
  bool confirmed = await showConfirmationDialog();
  if (confirmed) {
    // L'utente conferma di perdere il credito
    await forceUnsubscribeWithNoRefund(courseId, userId);
  }
} else {
  // Disiscrizione normale con rimborso
  await unsubscribeToCourse(courseId, userId);
}
```

## Componenti UI

### CourseUnsubscribeButton
- **Pulsante intelligente** che mostra già in anticipo se serve conferma
- **Colori diversi**: 
  - 🟠 Arancione: Richiede conferma (≤ 8 ore)
  - 🔴 Rosso: Disiscrizione normale (> 8 ore)
- **Testo dinamico**: "Disiscriviti (Perdi Credito)" vs "Disiscriviti"
- **Messaggi informativi** con icone appropriate

### CourseUnsubscribeHelper
- **Verifica preventiva** se serve conferma
- **Gestione automatica** del flusso di disiscrizione
- **Dialog di conferma** per perdita credito
- **Gestione errori** centralizzata

## Controlli di Sicurezza

1. **Transazioni Atomiche**: Tutte le operazioni usano Firestore transactions
2. **Validazione Utente**: Controllo esistenza corso e utente
3. **Gestione Errori**: Messaggi specifici per ogni tipo di errore
4. **Cache Management**: Invalida cache dopo modifiche
5. **Controllo Preventivo**: Verifica requisiti prima di mostrare UI

## Note Tecniche

- **Nessuna eccezione per il flusso**: La logica di conferma è gestita preventivamente
- **UI reattiva**: I pulsanti si adattano automaticamente ai requisiti
- **Gestione asincrona** con loading states
- **Logging completo** per debugging
- **Compatibilità** con sistema di cache esistente

## Modello multi-abbonamento (display/eligibility, da PR2)

In parallelo al modello legacy sopra, `getCourseState` supporta il nuovo modello
multi-abbonamento (`FitropeUser.activeSubscriptions`, lista di `UserSubscription`).

- **Selezione del modello** (aggiornata in PR4): se `activeSubscriptions` non
  contiene **voci non scadute** → modello legacy (invariato, zero regressione).
  Se contiene almeno una voce viva → modello multi-abbonamento. Le voci scadute
  rispetto ad adesso vengono scartate su entrambi i lati (vedi sezione
  "Snapshot stantio" sopra).
- **Tipologia primaria del corso**: primo tag riconosciuto (`CourseTypes.primaryForTags`,
  fallback `Open`). Determina deterministicamente quale famiglia "consuma" il corso
  (un corso multi-tag non è servito da più famiglie).
- **Copertura**: gli abbonamenti i cui `courseTypeTags` contengono la tipologia primaria.
- **Accesso**: tag legacy (`canUserAccessCourse`) **OPPURE** copertura abbonamento.
  I corsi accessibili solo via tag e senza famiglia (es. Hey Mamma) non hanno limiti.
- **Validità**: un abbonamento conta solo se `startDate ≤ dataCorso ≤ endDate`
  (scadenza per-abbonamento; se nessuno valido → `EXPIRED`).
- **Idoneità** (idoneo se ALMENO un abbonamento valido consente):
  - `FREQUENCY`: `weeklyFrequency` ingressi/settimana **per tipologia** (corsi della
    stessa tipologia + disiscrizioni perse nella settimana); `null` = illimitato.
  - `ENTRIES`: `remainingEntries > 0`.

### Vincolo di sequenza (PR3/PR4) — RISOLTO in PR4

In PR2/PR3 valeva il vincolo: `assignSubscription` non doveva andare in produzione
prima del write-path server-side, perché `subscribeToCourse` era ancora legacy e
non scalava `remainingEntries`. **Da PR4 il vincolo è soddisfatto**: il server
applica eligibility e decremento per il modello multi-abbonamento, e la UI di
assegnazione (`AssignSubscriptionCard` in UserDetailPage) non è più gated dietro
`kDebugMode`. PR3+PR4 vanno deployate **insieme** (stesso deploy functions).

### Display multi-abbonamento (PR7, solo lettura)

La UI rispecchia il nuovo modello senza scrivere nulla (le scritture restano
server-side):

- **Etichette** (`lib/utils/subscription_labels.dart`, pure/testate): pendant
  del legacy `getTipologiaIscrizioneLabel`. `getSubscriptionTitle` usa il
  `displayName` del catalogo (fallback famiglia + variante STABILE per piani
  fuori catalogo, senza il conteggio residui), `getSubscriptionAllowanceLabel`
  rende residui (ENTRIES, clampati a 0) / frequenza settimanale o "Accessi
  illimitati" (FREQUENCY), `getSubscriptionStatusLabel` lo stato ("Scade
  oggi"/singolare "1 giorno"/"Valido"/"Scaduto"/"Esaurito" per i pacchetti a
  ingressi con residui a zero — coerente col blocco `SUBSCRIBE_LIMIT` di
  `getCourseState`). `liveSubscriptions()` filtra
  le voci scadute con lo **stesso criterio** di `getCourseState` (`now` non
  successivo a `endDate`): display ed eligibility restano allineati.
- **HomePage** (`renderSubscriptionCard`): se lo snapshot ha voci vive mostra una
  `ActiveSubscriptionCard` per abbonamento; altrimenti fallback alla card legacy
  (zero regressione). NB: un abbonamento vivo SOSTITUISCE la card legacy (lo
  snapshot vince, come in `getCourseState`).
- **UserDetailPage**: sezione read-only "Abbonamenti attivi" che mostra TUTTE le
  voci snapshot (anche scadute: vista gestionale/storica), ordinate per scadenza.
- **AdminDashboardPage**: distribuzione "Per famiglia abbonamento" (dagli
  `activeSubscriptions` vivi) accanto a quella legacy per tipologia.

`ActiveSubscriptionCard` (`lib/components/`) colora la scadenza via
`AbbonamentoHelper` (verde valido / arancio in scadenza / rosso scaduto).

Superfici admin ancora **legacy-only** (cieche agli utenti convertiti, rinviate
al PR di pulizia legacy): lista/KPI "in scadenza" (`getUsersWithExpiringSubscriptions`,
query su `fineIscrizione`) e filtri `AdminUsersPage`. Vedi `docs/AVANZAMENTO_sale_pacchetti.md`.
