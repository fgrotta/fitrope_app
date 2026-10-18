import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:fitrope_app/state/simulation_session.dart';

/// Crea o aggiorna l'utente OneSignal con la sua email subscription.
/// Va chiamata al login così le email possono essere inviate via
/// `include_aliases.external_id` senza dipendere dal Web SDK.
Future<void> ensureOneSignalUser(String externalId, String email) async {
  SimulationSession.assertNotSimulating('ensureOneSignalUser');
  debugPrint(
      '🔔 [OneSignal API] ensureUser — externalId: $externalId, email: $email');

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('ensureOneSignalUser');
    final result = await callable.call({
      'externalId': externalId,
      'email': email,
    });
    debugPrint('🔔 [OneSignal API] ensureUser — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint('🔔 [OneSignal API] ensureUser — ERROR ${e.code}: ${e.message}');
  } catch (e) {
    debugPrint('🔔 [OneSignal API] ensureUser — ERROR: $e');
  }
}

/// Disabilita la subscription email OneSignal dell'utente autenticato.
/// Serve per il logout web, dove l'email viene registrata lato backend.
Future<void> removeOneSignalEmail(String email) async {
  SimulationSession.assertNotSimulating('removeOneSignalEmail');
  debugPrint('🔔 [OneSignal API] removeEmail — email: $email');

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('removeOneSignalEmail');
    final result = await callable.call({
      'email': email,
    });
    debugPrint('🔔 [OneSignal API] removeEmail — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint(
        '🔔 [OneSignal API] removeEmail — ERROR ${e.code}: ${e.message}');
  } catch (e) {
    debugPrint('🔔 [OneSignal API] removeEmail — ERROR: $e');
  }
}

// ──────────────────────────────────────────────
//  Promemoria lezione di prova e notifiche waitlist
// ──────────────────────────────────────────────
// Spostati server-side (PR4/PR5): promemoria prova nella Cloud Function
// `subscribeToCourse`, notifica waitlist in `unsubscribeFromCourse`/admin
// (functions/src/enrollment/notify.ts). Restano qui solo gli invii di test
// da DebugEmailPage (sendTest*, sotto).

Future<void> _sendTestEnrollmentEmail(Map<String, dynamic> data) async {
  SimulationSession.assertNotSimulating('sendTestEnrollmentEmail');
  assert(kDebugMode);
  final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
      .httpsCallable('sendTestEnrollmentEmail');
  final result = await callable.call(data);
  final response = Map<String, dynamic>.from(result.data as Map);
  if (response['suppressed'] == true) {
    throw StateError('Email di test non inviata: destinatario non abilitato');
  }
  debugPrint(
      '🔔 [OneSignal API] Enrollment Email [TEST] — RESPONSE: $response');
}

Future<void> sendTestWaitlistEmail({
  required String userId,
  required String courseName,
  required String courseDate,
  required String courseTime,
  required int spotsAvailable,
}) {
  SimulationSession.assertNotSimulating('sendTestWaitlistEmail');
  return _sendTestEnrollmentEmail({
    'externalId': userId,
    'kind': 'waitlist',
    'courseName': courseName,
    'courseDate': courseDate,
    'courseTime': courseTime,
    'spotsAvailable': spotsAvailable,
  });
}

Future<void> sendTestTrialReminderEmail({
  required String userId,
  required String courseName,
  required String courseDate,
  required String courseTime,
  required String courseId,
  required DateTime eventStart,
  required DateTime eventEnd,
  String? sala,
}) {
  SimulationSession.assertNotSimulating('sendTestTrialReminderEmail');
  return _sendTestEnrollmentEmail({
    'externalId': userId,
    'kind': 'trialReminder',
    'courseName': courseName,
    'courseDate': courseDate,
    'courseTime': courseTime,
    'courseId': courseId,
    'startMillis': eventStart.millisecondsSinceEpoch,
    'endMillis': eventEnd.millisecondsSinceEpoch,
    if (sala != null) 'sala': sala,
  });
}

/// Conferma demo con gli stessi template e link calendario dell'invio reale.
Future<void> sendTestTrialConfirmationEmail({
  required String userId,
  required String courseName,
  required String courseDate,
  required String courseTime,
  required String courseId,
  required DateTime eventStart,
  required DateTime eventEnd,
  String? sala,
}) {
  SimulationSession.assertNotSimulating('sendTestTrialConfirmationEmail');
  return _sendTestEnrollmentEmail({
    'externalId': userId,
    'kind': 'trialConfirmation',
    'courseName': courseName,
    'courseDate': courseDate,
    'courseTime': courseTime,
    'courseId': courseId,
    'startMillis': eventStart.millisecondsSinceEpoch,
    'endMillis': eventEnd.millisecondsSinceEpoch,
    if (sala != null) 'sala': sala,
  });
}

/// Invia un'email di test sulla scadenza del certificato medico.
/// Il template vive server-side (TS), quindi passa per la callable dedicata
/// `sendTestCertificateEmail` che renderizza e invia. `isExpiryDay` sceglie tra
/// l'email "10 giorni prima" (false) e quella "scadenza oggi" (true).
Future<void> sendTestCertificateExpiryEmail({
  required String userId,
  required String firstName,
  required String email,
  required bool isExpiryDay,
}) async {
  SimulationSession.assertNotSimulating('sendTestCertificateEmail');
  assert(kDebugMode);
  final kind = isExpiryDay ? 'expiryToday' : 'reminder10';
  debugPrint(
      '🔔 [OneSignal API] Certificate Email [TEST] — userId: $userId, kind: $kind');
  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('sendTestCertificateEmail');
    final result = await callable.call({
      'externalId': userId,
      'firstName': firstName,
      'email': email,
      'kind': kind,
    });
    debugPrint(
        '🔔 [OneSignal API] Certificate Email [TEST] — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint(
        '🔔 [OneSignal API] Certificate Email [TEST] — ERROR ${e.code}: ${e.message}');
    rethrow;
  } catch (e) {
    debugPrint('🔔 [OneSignal API] Certificate Email [TEST] — ERROR: $e');
    rethrow;
  }
}

/// Manda un payload di prova al webhook Make verso [numeroTelefono] e
/// restituisce l'esito e il body effettivamente inviato, così la pagina di
/// debug può mostrarlo. Lato server richiede il ruolo Admin e
/// WHATSAPP_DEMO_MODE=test|live. [kind] vale `'booked'` (tipo `conferma`) o
/// `'reminder'` (tipo `promemoria`); i campi vuoti ricadono su default.
Future<({bool ok, int status, Map<String, String> payload})>
    sendTestDemoLessonWebhook({
  required String numeroTelefono,
  String kind = 'booked',
  String? nome,
  String? corso,
  String? giorno,
  String? orario,
}) async {
  SimulationSession.assertNotSimulating('sendTestDemoLessonWebhook');
  assert(kDebugMode);
  debugPrint('📲 [Make] test webhook — kind: $kind');
  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('sendTestDemoLessonWebhook');
    final result = await callable.call({
      'numeroTelefono': numeroTelefono,
      'kind': kind,
      'nome': nome ?? '',
      'corso': corso ?? '',
      'giorno': giorno ?? '',
      'orario': orario ?? '',
    });
    debugPrint('📲 [Make] test webhook — RESPONSE: ${result.data}');
    final data = (result.data as Map<Object?, Object?>?) ?? const {};
    final payload = (data['payload'] as Map<Object?, Object?>?) ?? const {};
    return (
      ok: data['ok'] == true,
      status: (data['status'] as num?)?.toInt() ?? 0,
      payload: payload.map((key, value) => MapEntry('$key', '$value')),
    );
  } on FirebaseFunctionsException catch (e) {
    debugPrint('📲 [Make] test webhook — ERROR ${e.code}: ${e.message}');
    rethrow;
  } catch (e) {
    debugPrint('📲 [Make] test webhook — ERROR: $e');
    rethrow;
  }
}
