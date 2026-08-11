import 'package:fitrope_app/api/courses/enrollment_callable.dart';

/// Iscrive [userId] alla lista d'attesa di [courseId] tramite la Cloud Function
/// `joinWaitlist` (server-authoritative: corso pieno, flag `waitlistEnabled`,
/// duplicati e già-iscritto sono validati in transazione lato server).
Future<void> joinWaitlist(String courseId, String userId) {
  return callEnrollmentFunction(
    'joinWaitlist',
    <String, dynamic>{
      'courseId': courseId,
      'userId': userId,
    },
    userId: userId,
    fallbackError: 'Errore durante l\'iscrizione alla lista d\'attesa',
  );
}
