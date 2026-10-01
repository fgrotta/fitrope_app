import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/italian_time.dart';

/// Finestre delle presenze, mirror di `functions/src/enrollment/attendance.ts`
/// (il server resta l'autorità: qui si decide solo cosa mostrare).
const Duration selfCheckInBefore = Duration(minutes: 15);
const Duration selfCheckInAfter = Duration(minutes: 30);
const Duration staffMarkBefore = Duration(minutes: 30);

/// Cosa vede il socio iscritto sulla card del corso.
enum SelfCheckInState {
  /// Prima di 15' dall'inizio: niente (evita altezza extra sulle card future).
  notYetOpen,

  /// Bottone "Sono in sala".
  open,

  /// Finestra scaduta senza registrazione: "chiedi al trainer".
  closedAskTrainer,

  /// Check-in fatto dal socio.
  presentSelf,

  /// Presenza registrata dallo staff.
  presentStaff,

  /// Lo staff lo ha segnato assente.
  absentStaff,
}

/// Stato del check-in per il socio. `null` se non è iscritto, oppure se la
/// finestra è chiusa e il giorno del corso (Roma) è passato: l'avviso "chiedi
/// al trainer" su tutte le card vecchie sarebbe solo rumore.
///
/// Il record vince sul tempo; la finestra è inclusiva `[-15', +30']`.
/// NB: non deriva da `CourseState`, che diventa CLOSED appena il corso inizia.
SelfCheckInState? selfCheckInState(
  Course course,
  AttendanceRecord? record,
  DateTime now, {
  required bool isSubscribed,
}) {
  if (!isSubscribed) return null;
  if (record != null) {
    if (record.isStaffRecorded) {
      return record.present
          ? SelfCheckInState.presentStaff
          : SelfCheckInState.absentStaff;
    }
    if (record.present) return SelfCheckInState.presentSelf;
  }
  final start = course.startDate.toDate();
  if (now.isBefore(start.subtract(selfCheckInBefore))) {
    return SelfCheckInState.notYetOpen;
  }
  if (!now.isAfter(start.add(selfCheckInAfter))) return SelfCheckInState.open;
  if (now.isBefore(_endOfCourseDay(course))) {
    return SelfCheckInState.closedAskTrainer;
  }
  return null;
}

/// Lo staff può fare l'appello da 30' prima dell'inizio, senza scadenza.
bool staffCanMark(Course course, DateTime now) =>
    !now.isBefore(course.startDate.toDate().subtract(staffMarkBefore));

/// Primo istante dopo [now] in cui cambia qualcosa di quanto sopra: la card
/// ci aggancia un Timer one-shot per ricostruirsi (nessun rebuild altrimenti
/// scatterebbe allo scadere di una finestra). `null` = niente più confini.
DateTime? nextAttendanceBoundary(Course course, DateTime now) {
  final start = course.startDate.toDate();
  final boundaries = [
    start.subtract(staffMarkBefore),
    start.subtract(selfCheckInBefore),
    // La finestra self è inclusiva: chiude al millisecondo dopo +30'.
    start.add(selfCheckInAfter).add(const Duration(milliseconds: 1)),
    _endOfCourseDay(course),
  ];
  for (final b in boundaries) {
    if (b.isAfter(now)) return b;
  }
  return null;
}

bool isMarkedPresent(AttendanceRecord? record) => record?.present == true;

/// Mezzanotte (Roma) successiva all'inizio del corso.
DateTime _endOfCourseDay(Course course) {
  final local = toItalianTime(course.startDate.toDate());
  return italianTimestamp(DateTime(local.year, local.month, local.day + 1))
      .toDate();
}
