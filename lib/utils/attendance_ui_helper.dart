import 'package:fitrope_app/api/courses/set_attendance.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';

/// Chiamate UI delle presenze condivise tra le pagine. La guardia
/// `SimulationGuard.blockIfSimulating` resta la PRIMA istruzione del callback
/// nella pagina, prima di arrivare qui.
///
/// Nessun `updateCourses()` dopo: ricaricare i corsi collasserebbe la card
/// aperta nel mezzo dell'appello. Lo stato locale lo aggiorna la card.
class AttendanceUiHelper {
  /// "Sono in sala" del socio, con il Loader globale (tap singolo, come
  /// "Prenotati"). Ritorna true se il server ha registrato la presenza.
  static Future<bool> selfCheckIn({
    required BuildContext context,
    required Course course,
    required bool Function() isMounted,
  }) async {
    try {
      await setAttendance(courseId: course.uid, present: true);
      if (isMounted() && context.mounted) {
        SnackBarUtils.showSuccessSnackBar(context, 'Presenza registrata');
      }
      return true;
    } catch (e) {
      debugPrint('setAttendance (self) failed: $e');
      if (isMounted() && context.mounted) {
        SnackBarUtils.showErrorSnackBar(context, attendanceErrorMessage(e));
      }
      return false;
    }
  }

  /// Appello dello staff: spinner sulla riga, niente Loader full-screen.
  static Future<bool> markAttendance({
    required BuildContext context,
    required Course course,
    required String userId,
    required bool present,
    required bool Function() isMounted,
  }) async {
    try {
      await setAttendance(
        courseId: course.uid,
        userId: userId,
        present: present,
        showGlobalLoader: false,
      );
      return true;
    } catch (e) {
      debugPrint('setAttendance (staff) failed: $e');
      if (isMounted() && context.mounted) {
        SnackBarUtils.showErrorSnackBar(context, attendanceErrorMessage(e));
      }
      return false;
    }
  }
}
