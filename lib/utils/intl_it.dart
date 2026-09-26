import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart' show Intl;

/// Formattazione date solo in italiano, senza `date_symbol_data_local` (che
/// porta nel bundle e inizializza i dati di tutte le lingue prima del
/// `runApp`).
///
/// Dati copiati da `intl-0.20.2/lib/src/data/dates/{symbols,patterns}/it.json`:
/// se si aggiorna `intl` e cambiano, vanno ricopiati. `'it_IT'` ricade su
/// `'it'` via `Intl.verifiedLocale`.
///
/// Sono gli UNICI dati di date registrati: l'app non usa i delegate
/// `Global*Localizations` (vedi `italian_localizations.dart`), che
/// registrerebbero tutte le lingue. Per questo la locale di default diventa
/// `it_IT`: un `DateFormat` senza locale cercherebbe altrimenti la locale di
/// sistema (`en_US`) e lancerebbe "Invalid locale".
void initializeItalianDateFormatting() {
  initializeDateFormattingCustom(
    locale: 'it',
    symbols: DateSymbols.deserializeFromMap(_itSymbols),
    patterns: _itPatterns,
  );
  Intl.defaultLocale = 'it_IT';
}

const Map<String, Object?> _itSymbols = {
  'NAME': 'it',
  'ERAS': ['a.C.', 'd.C.'],
  'ERANAMES': ['avanti Cristo', 'dopo Cristo'],
  'NARROWMONTHS': ['G', 'F', 'M', 'A', 'M', 'G', 'L', 'A', 'S', 'O', 'N', 'D'],
  'STANDALONENARROWMONTHS': [
    'G',
    'F',
    'M',
    'A',
    'M',
    'G',
    'L',
    'A',
    'S',
    'O',
    'N',
    'D'
  ],
  'MONTHS': [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre'
  ],
  'STANDALONEMONTHS': [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre'
  ],
  'SHORTMONTHS': [
    'gen',
    'feb',
    'mar',
    'apr',
    'mag',
    'giu',
    'lug',
    'ago',
    'set',
    'ott',
    'nov',
    'dic'
  ],
  'STANDALONESHORTMONTHS': [
    'gen',
    'feb',
    'mar',
    'apr',
    'mag',
    'giu',
    'lug',
    'ago',
    'set',
    'ott',
    'nov',
    'dic'
  ],
  'WEEKDAYS': [
    'domenica',
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato'
  ],
  'STANDALONEWEEKDAYS': [
    'domenica',
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato'
  ],
  'SHORTWEEKDAYS': ['dom', 'lun', 'mar', 'mer', 'gio', 'ven', 'sab'],
  'STANDALONESHORTWEEKDAYS': ['dom', 'lun', 'mar', 'mer', 'gio', 'ven', 'sab'],
  'NARROWWEEKDAYS': ['D', 'L', 'M', 'M', 'G', 'V', 'S'],
  'STANDALONENARROWWEEKDAYS': ['D', 'L', 'M', 'M', 'G', 'V', 'S'],
  'SHORTQUARTERS': ['T1', 'T2', 'T3', 'T4'],
  'QUARTERS': ['1º trimestre', '2º trimestre', '3º trimestre', '4º trimestre'],
  'AMPMS': ['m.', 'p.'],
  'DATEFORMATS': ['EEEE d MMMM y', 'd MMMM y', 'd MMM y', 'dd/MM/yy'],
  'TIMEFORMATS': ['HH:mm:ss zzzz', 'HH:mm:ss z', 'HH:mm:ss', 'HH:mm'],
  'AVAILABLEFORMATS': null,
  'FIRSTDAYOFWEEK': 0,
  'WEEKENDRANGE': [5, 6],
  'FIRSTWEEKCUTOFFDAY': 3,
  'DATETIMEFORMATS': ['{1} {0}', '{1} {0}', '{1}, {0}', '{1}, {0}'],
};

const Map<String, String> _itPatterns = {
  'd': 'd',
  'E': 'ccc',
  'EEEE': 'cccc',
  'LLL': 'LLL',
  'LLLL': 'LLLL',
  'M': 'L',
  'Md': 'dd/MM',
  'MEd': 'EEE dd/MM',
  'MMM': 'LLL',
  'MMMd': 'd MMM',
  'MMMEd': 'EEE d MMM',
  'MMMM': 'LLLL',
  'MMMMd': 'd MMMM',
  'MMMMEEEEd': 'EEEE d MMMM',
  'QQQ': 'QQQ',
  'QQQQ': 'QQQQ',
  'y': 'y',
  'yM': 'MM/y',
  'yMd': 'dd/MM/y',
  'yMEd': 'EEE dd/MM/y',
  'yMMM': 'MMM y',
  'yMMMd': 'd MMM y',
  'yMMMEd': 'EEE d MMM y',
  'yMMMM': 'MMMM y',
  'yMMMMd': 'd MMMM y',
  'yMMMMEEEEd': 'EEEE d MMMM y',
  'yQQQ': 'QQQ y',
  'yQQQQ': 'QQQQ y',
  'H': 'HH',
  'Hm': 'HH:mm',
  'Hms': 'HH:mm:ss',
  'j': 'HH',
  'jm': 'HH:mm',
  'jms': 'HH:mm:ss',
  'jmv': 'HH:mm v',
  'jmz': 'HH:mm z',
  'jz': 'HH z',
  'm': 'm',
  'ms': 'mm:ss',
  's': 's',
  'v': 'v',
  'z': 'z',
  'zzzz': 'zzzz',
  'ZZZZ': 'ZZZZ',
};
