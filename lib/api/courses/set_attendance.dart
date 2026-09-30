import 'package:fitrope_app/api/courses/enrollment_callable.dart';
import 'package:fitrope_app/api/courses/get_attendance.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/types/attendance_record.dart';

/// Esito di `setAttendance`, come lo restituisce la callable.
class SetAttendanceResult {
  final bool present;
  final AttendanceSource source;

  /// false = la richiesta ripeteva lo stato già registrato (doppio tap).
  final bool changed;
  final int presentCount;

  const SetAttendanceResult({
    required this.present,
    required this.source,
    required this.changed,
    required this.presentCount,
  });

  factory SetAttendanceResult.fromJson(Map<String, dynamic> json) {
    return SetAttendanceResult(
      present: json['present'] == true,
      source: AttendanceSource.fromString(json['source'] as String?),
      changed: json['changed'] != false,
      presentCount: (json['presentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Registra una presenza tramite la Cloud Function `setAttendance`.
///
/// [userId] null = check-in del chiamante ("Sono in sala"); valorizzato =
/// appello dello staff. Nessun refresh dell'utente: le presenze non toccano il
/// suo documento. [showGlobalLoader] false per l'appello, che mostra uno
/// spinner per riga invece del Loader full-screen.
Future<SetAttendanceResult> setAttendance({
  required String courseId,
  String? userId,
  required bool present,
  bool showGlobalLoader = true,
}) async {
  SimulationSession.assertNotSimulating('setAttendance');
  final data = await callEnrollmentFunction(
    'setAttendance',
    <String, dynamic>{
      'courseId': courseId,
      if (userId != null) 'userId': userId,
      'present': present,
    },
    fallbackError: 'Errore durante la registrazione della presenza',
    showGlobalLoader: showGlobalLoader,
  ).whenComplete(invalidateAttendanceCache);
  return SetAttendanceResult.fromJson(data);
}

/// Motivi di rifiuto di `setAttendance` (`details.reason` della callable).
enum AttendanceRejectReason {
  staffCannotSelfMark('ATTENDANCE_STAFF_CANNOT_SELF_MARK'),
  notStaff('ATTENDANCE_NOT_STAFF'),
  notCourseTrainer('ATTENDANCE_NOT_COURSE_TRAINER'),
  selfCannotMarkAbsent('ATTENDANCE_SELF_CANNOT_MARK_ABSENT'),
  notEnrolled('ATTENDANCE_NOT_ENROLLED'),
  windowNotOpen('ATTENDANCE_WINDOW_NOT_OPEN'),
  windowClosed('ATTENDANCE_WINDOW_CLOSED'),
  alreadyRecordedByStaff('ATTENDANCE_ALREADY_RECORDED_BY_STAFF');

  final String code;
  const AttendanceRejectReason(this.code);

  static AttendanceRejectReason? fromCode(String? code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

final RegExp _reasonInMessage = RegExp(r'ATTENDANCE_[A-Z_]+');

/// Legge la reason da `details.reason`; in mancanza la cerca nel messaggio.
AttendanceRejectReason? attendanceRejectReason(Object error) {
  if (error is! EnrollmentException) return null;
  final details = error.details;
  if (details is Map) {
    final fromDetails = AttendanceRejectReason.fromCode(
      details['reason'] as String?,
    );
    if (fromDetails != null) return fromDetails;
  }
  return AttendanceRejectReason.fromCode(
    _reasonInMessage.firstMatch(error.message)?.group(0),
  );
}

/// Messaggio italiano per l'utente; per errori non riconosciuti il testo
/// originale (già leggibile, vedi [EnrollmentException.toString]).
String attendanceErrorMessage(Object error) {
  switch (attendanceRejectReason(error)) {
    case AttendanceRejectReason.windowClosed:
      return 'Check-in chiuso: chiedi al trainer di registrare la tua presenza';
    case AttendanceRejectReason.windowNotOpen:
      return 'La registrazione delle presenze non è ancora aperta';
    case AttendanceRejectReason.alreadyRecordedByStaff:
      return 'Presenza già registrata dallo staff';
    case AttendanceRejectReason.notCourseTrainer:
      return 'Puoi registrare le presenze solo dei tuoi corsi';
    case AttendanceRejectReason.notEnrolled:
      return 'L\'utente non è iscritto a questo corso';
    case AttendanceRejectReason.notStaff:
      return 'Solo lo staff può registrare la presenza di un altro utente';
    case AttendanceRejectReason.staffCannotSelfMark:
      return 'Admin e Trainer non registrano la propria presenza';
    case AttendanceRejectReason.selfCannotMarkAbsent:
      return 'Puoi solo segnalare la tua presenza';
    case null:
      return error.toString();
  }
}
