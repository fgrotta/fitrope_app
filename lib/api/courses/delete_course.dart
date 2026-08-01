import 'package:fitrope_app/api/courses/enrollment_callable.dart';

/// Rimozione admin/trainer di un utente da un corso tramite la Cloud Function
/// `unsubscribeFromCourse` (server-authoritative).
///
/// Il server riconosce l'operazione admin (chiamante ≠ utente target) e applica
/// la regola "admin rimborsa sempre": nessuna finestra 4h/8h, ripristino della
/// fonte realmente consumata (registro consumi: entrate legacy O ingressi
/// abbonamento), nessuna voce in cancelledEnrollments. Fix rispetto al legacy:
/// ora il contatore `subscribed` viene decrementato anche qui (il vecchio
/// removeUserFromCourse non lo faceva: era l'origine delle discrepanze).
Future<void> removeUserFromCourse(String courseId, String userId) {
  return callEnrollmentFunction(
    'unsubscribeFromCourse',
    <String, dynamic>{
      'courseId': courseId,
      'userId': userId,
    },
    userId: userId,
    fallbackError: 'Errore durante la rimozione dal corso',
  );
}

/// Cancella un corso tramite la Cloud Function `deleteCourse` (Admin/Trainer):
/// UNA transazione atomica che rimborsa tutti gli iscritti (registro consumi,
/// regola admin-rimborsa-sempre), ripulisce le waitlist ed elimina il corso.
/// A differenza del legacy, NESSUNA email "posto disponibile" alla waitlist
/// (il corso sta sparendo) e nessuna catena di N transazioni non atomiche.
Future<void> deleteCourse(String courseId) {
  return callEnrollmentFunction(
    'deleteCourse',
    <String, dynamic>{'courseId': courseId},
    fallbackError: 'Errore durante la cancellazione del corso',
  );
}
