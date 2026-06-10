import 'package:fitrope_app/api/courses/enrollment_callable.dart';

class WaitlistRemovalResult {
  final List<dynamic> updatedCourseWaitlist;
  final List<dynamic> updatedUserWaitlistCourses;
  final bool removedFromCourse;
  final bool removedFromUser;

  const WaitlistRemovalResult({
    required this.updatedCourseWaitlist,
    required this.updatedUserWaitlistCourses,
    required this.removedFromCourse,
    required this.removedFromUser,
  });

  bool get hasChanges => removedFromCourse || removedFromUser;
}

/// Logica pura di rimozione dalla waitlist (corso + utente). È la specifica
/// condivisa con il server: `leaveWaitlistHandler` (functions/src/enrollment)
/// applica le stesse regole in transazione, inclusa la pulizia dei dati
/// incoerenti (presente su un solo lato).
WaitlistRemovalResult computeWaitlistRemoval({
  required List<dynamic> courseWaitlist,
  required List<dynamic> userWaitlistCourses,
  required String userId,
  required String courseId,
}) {
  final updatedCourseWaitlist = List<dynamic>.from(courseWaitlist);
  final updatedUserWaitlistCourses = List<dynamic>.from(userWaitlistCourses);

  final removedFromCourse = updatedCourseWaitlist.remove(userId);
  final removedFromUser = updatedUserWaitlistCourses.remove(courseId);

  return WaitlistRemovalResult(
    updatedCourseWaitlist: updatedCourseWaitlist,
    updatedUserWaitlistCourses: updatedUserWaitlistCourses,
    removedFromCourse: removedFromCourse,
    removedFromUser: removedFromUser,
  );
}

/// Rimuove [userId] dalla lista d'attesa di [courseId] tramite la Cloud
/// Function `leaveWaitlist` (server-authoritative).
Future<void> leaveWaitlist(String courseId, String userId) {
  return callEnrollmentFunction(
    'leaveWaitlist',
    <String, dynamic>{
      'courseId': courseId,
      'userId': userId,
    },
    userId: userId,
    fallbackError: 'Errore durante la rimozione dalla lista d\'attesa',
  );
}
