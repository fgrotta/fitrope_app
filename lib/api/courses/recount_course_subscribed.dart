import 'package:fitrope_app/api/courses/enrollment_callable.dart';

/// Ricalcola il contatore iscritti di un corso tramite la Cloud Function
/// `recountCourseSubscribed` (Admin/Trainer).
///
/// Sostituisce la vecchia correzione manuale client-side: il valore non viene
/// più calcolato (né passato) dal client — il server conta gli utenti con il
/// corso in `courses[]` e scrive il risultato in transazione, senza rischiare
/// di sovrascrivere iscrizioni concorrenti.
Future<void> recountCourseSubscribed(String courseId) {
  return callEnrollmentFunction(
    'recountCourseSubscribed',
    <String, dynamic>{'courseId': courseId},
    fallbackError: 'Errore durante il ricalcolo del conteggio iscritti',
  );
}
