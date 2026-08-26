import 'package:firebase_core/firebase_core.dart';

/// Mirror client di `functions/src/enrollment/calendarLinks.ts`.
///
/// La copia **autoritativa** è quella TypeScript: le email reali (conferma
/// iscrizione prova e promemoria) sono composte server-side. Questo file serve
/// alle email di test di `DebugEmailPage`, così il template renderizzato in
/// debug ha bottoni cliccabili identici a quelli di produzione.
/// Se cambi gli URL qui, aggiorna anche il TS (e viceversa).

const int _icsEmulatorPort = 5001; // firebase.json > emulators.functions.port
const String _icsFunctionName = 'courseIcs';
const String _icsRegion = 'europe-west8';

/// Tenere allineato con `GYM_ADDRESS` in calendarLinks.ts.
const String gymAddress =
    'Fit House Monza, Via Giuseppe Ferrari, 6, 20900 Monza';

const String _eventDescription = "La tua lezione di prova alla Fit House. "
    "Ricordati abbigliamento comodo e una bottiglietta d'acqua.";

/// `YYYYMMDDTHHMMSSZ` (formato "basic" UTC di RFC 5545 / Google Calendar).
String formatUtcStamp(DateTime instant) {
  final d = instant.toUtc();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${pad(d.month)}${pad(d.day)}'
      'T${pad(d.hour)}${pad(d.minute)}${pad(d.second)}Z';
}

/// Luogo dell'evento: sala del corso (se valorizzata) + indirizzo palestra.
String eventLocation(String? sala) {
  final trimmed = sala?.trim();
  return (trimmed == null || trimmed.isEmpty)
      ? gymAddress
      : '$trimmed — $gymAddress';
}

/// Deeplink "crea evento" di Google Calendar.
String googleCalendarUrl({
  required String courseName,
  required DateTime start,
  required DateTime end,
  String? sala,
}) {
  final query = Uri(queryParameters: {
    'action': 'TEMPLATE',
    'text': courseName,
    'dates': '${formatUtcStamp(start)}/${formatUtcStamp(end)}',
    'details': _eventDescription,
    'location': eventLocation(sala),
  }).query;
  return 'https://calendar.google.com/calendar/render?$query';
}

/// Stesso dart-define letto da `main.dart`: e' una costante di compilazione,
/// quindi il valore e' identico senza dover passare dal main.
const bool _useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Link al file `.ics` servito dalla function HTTP `courseIcs`.
String icsUrl(String courseId) {
  final project = Firebase.app().options.projectId;
  const fn = '$_icsRegion/$_icsFunctionName';
  final base = _useEmulator
      ? 'http://127.0.0.1:$_icsEmulatorPort/$project/$fn'
      : 'https://$_icsRegion-$project.cloudfunctions.net/$_icsFunctionName';
  return '$base?courseId=${Uri.encodeComponent(courseId)}';
}
