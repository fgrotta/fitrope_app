# Sistema di Iscrizioni e Disiscrizione ai Corsi - FitRope

## Panoramica

Il sistema gestisce le iscrizioni ai corsi basandosi su due tipi principali di abbonamento:
- **Pacchetto Entrate**: Sistema a crediti con regole specifiche per i rimborsi
- **Abbonamenti Temporali**: Mensile, Trimestrale, Semestrale, Annuale con limiti settimanali

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
- `forceUnsubscribeFromCourse(courseId, userId)` - Disiscrizione forzata
- `deleteCourse(courseId)` - Cancellazione corso completo

**Importante**: Le funzioni admin **sempre** restituiscono il credito per i Pacchetti Entrate, indipendentemente dal tempo rimanente.

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

- **Selezione del modello**: se `activeSubscriptions` è **vuoto** → modello legacy
  (invariato, zero regressione). Se non è vuoto → modello multi-abbonamento.
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

### ⚠️ Vincolo di sequenza (PR3/PR4)

In PR2 questo è **solo read-path/display**: nessuno scrive `activeSubscriptions`
(le scritture arrivano dalle Cloud Functions in PR3+), quindi in produzione lo
snapshot è vuoto e vale sempre il fallback legacy → **PR2 non cambia comportamento
osservabile**. `subscribeToCourse`/`unsubscribeToCourse` sono ancora **solo legacy**
(non leggono `activeSubscriptions` né decrementano `remainingEntries`). Perciò
**`assignSubscription` (PR3) non deve andare in produzione prima che il write-path
server-side (PR4) applichi eligibility + decremento**, altrimenti gli ingressi
(ENTRIES) non verrebbero scalati. HomePage e label restano legacy fino a PR7.
