import 'package:fitrope_app/api/courses/enrollment_callable.dart';

/// Disiscrizione normale (rimborso quando dovuto) tramite la Cloud Function
/// `unsubscribeFromCourse` (server-authoritative).
///
/// Il server applica le finestre (8h ingressi / 4h frequenza): se la
/// disiscrizione ricade nella finestra senza conferma, la callable fallisce con
/// `failed-precondition` — il flusso UI deve passare da
/// [forceUnsubscribeWithNoRefund] dopo conferma esplicita dell'utente
/// (vedi CourseUnsubscribeHelper). Il rimborso ripristina la fonte realmente
/// consumata all'iscrizione (registro consumi server-side). La notifica
/// waitlist parte dal server.
Future<void> unsubscribeToCourse(String courseId, String userId) {
  return _unsubscribe(courseId, userId, confirmedNoRefund: false);
}

/// Disiscrizione confermata entro la finestra: l'utente accetta di perdere il
/// credito/ingresso settimanale. Fuori finestra il server rimborsa comunque
/// (la conferma è irrilevante: non si può perdere credito quando il rimborso
/// è dovuto).
Future<void> forceUnsubscribeWithNoRefund(String courseId, String userId) {
  return _unsubscribe(courseId, userId, confirmedNoRefund: true);
}

Future<void> _unsubscribe(String courseId, String userId,
    {required bool confirmedNoRefund}) {
  return callEnrollmentFunction(
    'unsubscribeFromCourse',
    <String, dynamic>{
      'courseId': courseId,
      'userId': userId,
      'confirmedNoRefund': confirmedNoRefund,
    },
    userId: userId,
    fallbackError: 'Errore durante la disiscrizione',
  );
}
