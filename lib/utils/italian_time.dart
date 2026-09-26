import 'package:cloud_firestore/cloud_firestore.dart';
// `latest_10y` (87 KB di dati contro i 384 KB di `latest`) copre le regole
// DST da gen 2019 a gen 2029 con timezone 0.9.4. Oltre quella data `Europe/Rome`
// resterebbe su CET tutto l'anno (orari estivi sbagliati di un'ora): va
// aggiornato il pacchetto `timezone`, e il test "latest_10y copre l'anno
// prossimo" in `test/italian_time_test.dart` fallisce per ricordarlo.
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Fuso orario di riferimento dell'app: l'orario mostrato e salvato è SEMPRE
/// quello italiano (Europe/Rome), indipendentemente dal fuso del dispositivo.
/// Gestisce automaticamente l'ora legale (CET/CEST).
const String _italianTzName = 'Europe/Rome';

tz.Location? _rome;

/// Inizializza il database dei fusi orari. Idempotente. Non serve chiamarla
/// all'avvio: parte in lazy alla prima conversione, cioè dopo il primo frame.
void initItalianTime() {
  if (_rome != null) return;
  tzdata.initializeTimeZones();
  _rome = tz.getLocation(_italianTzName);
}

tz.Location _location() {
  if (_rome == null) initItalianTime();
  return _rome!;
}

/// Converte un istante assoluto nell'orario italiano. Da usare per la
/// VISUALIZZAZIONE (estrazione di ora/minuti/giorno per la UI).
tz.TZDateTime toItalianTime(DateTime instant) =>
    tz.TZDateTime.from(instant, _location());

/// Interpreta i componenti wall-clock (anno/mese/giorno/ora/minuto) come
/// orario italiano e restituisce il Timestamp dell'istante assoluto
/// corrispondente. Da usare in SCRITTURA: così "19:00" significa sempre le
/// 19:00 italiane anche se il dispositivo che crea il corso è in un altro fuso.
Timestamp italianTimestamp(DateTime wallClock) => Timestamp.fromDate(
      tz.TZDateTime(
        _location(),
        wallClock.year,
        wallClock.month,
        wallClock.day,
        wallClock.hour,
        wallClock.minute,
        wallClock.second,
      ),
    );
