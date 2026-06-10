import 'package:fitrope_app/api/courses/enrollment_callable.dart';

/// Iscrive [userId] al corso [courseId] tramite la Cloud Function
/// `subscribeToCourse` (server-authoritative).
///
/// Idoneità (accesso, crediti/limiti, scadenza), capienza e decremento ingressi
/// sono applicati dal server in transazione: il client non scrive più su
/// corsi/utenti. [force] è onorato solo se il chiamante è Admin/Trainer.
/// Il promemoria della lezione di prova è schedulato dal server.
Future<void> subscribeToCourse(String courseId, String userId,
    {bool force = false, String? userRole}) async {
  // Guardia client (fail-fast, stessa regola enforceata dal server).
  if (userRole == 'Admin' || userRole == 'Trainer') {
    throw Exception('Admin e Trainer non possono iscriversi ai corsi');
  }

  await callEnrollmentFunction(
    'subscribeToCourse',
    <String, dynamic>{
      'courseId': courseId,
      'userId': userId,
      'force': force,
    },
    userId: userId,
    fallbackError: 'Errore durante l\'iscrizione',
  );
}
