# Gestione Disdette Tardive per Abbonamenti

## Panoramica

Questa funzionalità gestisce le disdette tardive per gli utenti con abbonamenti che hanno limiti settimanali (Trimestrale, Semestrale, Annuale). Quando un utente disdice una lezione nelle 2 ore precedenti all'inizio, la lezione viene conteggiata come "persa" per il limite settimanale.

## Logica di Business

### Abbonamenti Coinvolti
- **Abbonamento Trimestrale**
- **Abbonamento Semestrale** 
- **Abbonamento Annuale**

### Regole di Applicazione
1. **Finestra temporale**: 2 ore prima dell'inizio del corso
2. **Conteggio**: La lezione disdetta viene aggiunta al conteggio settimanale
3. **Effetto**: L'utente non può più iscriversi ad altre lezioni nella settimana corrente se ha raggiunto il limite

### Esempio Pratico
- Utente con abbonamento trimestrale (2 lezioni settimanali)
- Ha già frequentato 1 lezione questa settimana
- Disdice una lezione 1 ora prima dell'inizio
- **Risultato**: Non può più iscriversi ad altre lezioni questa settimana (1 frequentata + 1 disdetta tardiva = 2/2)

## Implementazione Tecnica

### Modifiche al Modello Dati

#### FitropeUser
```dart
final Map<String, int>? disdetteTardiveSettimanali; // "YYYY-WW" -> count
```

### Nuove Utility

#### WeekUtils
- `getWeekKey(DateTime date)`: Genera chiave settimana "YYYY-WW"
- `getWeekRange(DateTime date)`: Ottiene inizio/fine settimana
- `isDateInWeek(DateTime date, String weekKey)`: Controlla se data è in settimana
- `getDisdetteTardiveForWeek(Map, String)`: Conta disdette per settimana
- `incrementDisdetteTardive(Map, String)`: Incrementa contatore

### Modifiche alle API

#### unsubscribeToCourse
- Rileva abbonamenti con limiti settimanali
- Controlla finestra 2 ore per disdette tardive
- Incrementa contatore disdette tardive per settimana
- Lancia eccezione `CONFIRMATION_REQUIRED_ABBONAMENTO` per conferma

#### getCourseState
- Considera disdette tardive nel conteggio settimanale
- Blocca iscrizioni se limite raggiunto (lezioni + disdette tardive)

### Interfaccia Utente

#### CalendarPage
- Gestisce nuovo tipo di conferma per abbonamenti
- Mostra dialog specifico per disdette tardive
- Messaggio: "Questa lezione verrà conteggiata come persa per il limite settimanale"

#### UserDetailPage
- Mostra disdette tardive settimana corrente
- Mostra storico disdette tardive
- Informazioni visibili solo agli admin

## Flusso Utente

1. **Utente clicca "Disiscriviti"** su corso nelle 2 ore precedenti
2. **Sistema rileva** abbonamento con limiti settimanali
3. **Mostra dialog** di conferma con avviso specifico
4. **Utente conferma** la disiscrizione
5. **Sistema incrementa** contatore disdette tardive
6. **Aggiorna stato** corso per bloccare ulteriori iscrizioni

## Test e Validazione

### Scenari di Test
1. **Disdetta normale** (>2 ore): Nessun effetto sul limite settimanale
2. **Disdetta tardiva** (≤2 ore): Incrementa contatore disdette tardive
3. **Limite raggiunto**: Blocca iscrizioni per settimana corrente
4. **Nuova settimana**: Reset automatico del contatore

### File di Test
- `test_week_utils.dart`: Test unitari per utility settimanali

## Considerazioni Future

### Possibili Miglioramenti
1. **Notifiche**: Avvisare utente quando si avvicina al limite
2. **Grafici**: Visualizzazione trend disdette tardive
3. **Report**: Statistiche per admin su disdette tardive
4. **Configurazione**: Finestra temporale configurabile per tipo abbonamento

### Manutenzione
- Pulizia automatica disdette tardive vecchie (>1 anno)
- Backup periodico dati disdette tardive
- Monitoraggio performance query con nuovi campi 