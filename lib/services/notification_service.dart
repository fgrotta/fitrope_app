import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:fitrope_app/services/email_templates.dart';

String _testPrefix(String text) => kDebugMode ? 'TEST - $text' : text;

/// Helper per inviare una richiesta a OneSignal tramite Cloud Function.
/// La function tiene la REST API key server-side e gestisce CORS automaticamente.
Future<void> _sendOneSignalRequest(String label, Map<String, dynamic> body) async {
  final logBody = Map<String, dynamic>.from(body);
  logBody.remove('email_body');
  debugPrint('🔔 [OneSignal API] $label — REQUEST body: ${jsonEncode(logBody)}');

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('sendOneSignalNotification');
    final result = await callable.call(body);
    debugPrint('🔔 [OneSignal API] $label — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint('🔔 [OneSignal API] $label — ERROR ${e.code}: ${e.message}');
  } catch (e) {
    debugPrint('🔔 [OneSignal API] $label — ERROR: $e');
  }
}

/// Crea o aggiorna l'utente OneSignal con la sua email subscription.
/// Va chiamata al login così le email possono essere inviate via
/// `include_aliases.external_id` senza dipendere dal Web SDK.
Future<void> ensureOneSignalUser(String externalId, String email) async {
  debugPrint('🔔 [OneSignal API] ensureUser — externalId: $externalId, email: $email');

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
  debugPrint('🔔 [OneSignal API] removeEmail — email: $email');

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('removeOneSignalEmail');
    final result = await callable.call({
      'email': email,
    });
    debugPrint('🔔 [OneSignal API] removeEmail — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint('🔔 [OneSignal API] removeEmail — ERROR ${e.code}: ${e.message}');
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

Future<void> sendTestWaitlistEmail({
  required String userId,
  required String courseName,
  required String courseDate,
  required String courseTime,
  required int spotsAvailable,
}) {
  assert(kDebugMode);
  return _sendOneSignalRequest('Waitlist Email [TEST]', {
    'include_aliases': {'external_id': [userId]},
    'target_channel': 'email',
    'email_subject': _testPrefix(waitlistSpotAvailableSubject(courseName)),
    'email_body': waitlistSpotAvailableBody(
      courseName: courseName,
      courseDate: courseDate,
      courseTime: courseTime,
      spotsAvailable: spotsAvailable,
    ),
  });
}

Future<void> sendTestTrialReminderEmail({
  required String userId,
  required String courseName,
  required String courseDate,
  required String courseTime,
}) {
  assert(kDebugMode);
  return _sendOneSignalRequest('Trial Email Reminder [TEST]', {
    'include_aliases': {'external_id': [userId]},
    'target_channel': 'email',
    'email_subject': _testPrefix(trialReminderSubject(courseName)),
    'email_body': trialReminderBody(
      courseName: courseName,
      courseDate: courseDate,
      courseTime: courseTime,
    ),
  });
}
