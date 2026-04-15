import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:fitrope_app/services/email_templates.dart';

const List<String> _dayNames = [
  'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'
];

const List<String> _monthNames = [
  'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
  'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
];

String _testPrefix(String text) => kDebugMode ? 'TEST - $text' : text;

/// Helper per inviare una richiesta a OneSignal tramite Cloud Function.
/// La function tiene la REST API key server-side e gestisce CORS automaticamente.
Future<void> _sendOneSignalRequest(String label, Map<String, dynamic> body) async {
  final logBody = Map<String, dynamic>.from(body);
  logBody.remove('email_body');
  debugPrint('🔔 [OneSignal API] $label — REQUEST body: ${jsonEncode(logBody)}');

  try {
    final callable = FirebaseFunctions.instance.httpsCallable('sendOneSignalNotification');
    final result = await callable.call(body);
    debugPrint('🔔 [OneSignal API] $label — RESPONSE: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    debugPrint('🔔 [OneSignal API] $label — ERROR ${e.code}: ${e.message}');
  } catch (e) {
    debugPrint('🔔 [OneSignal API] $label — ERROR: $e');
  }
}

String _formatCourseDate(DateTime startDate) {
  return '${_dayNames[startDate.weekday - 1]} ${startDate.day} ${_monthNames[startDate.month - 1]} ${startDate.year}';
}

String _formatCourseTime(DateTime startDate, DateTime endDate) {
  return '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}'
      ' - '
      '${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}';
}

// ──────────────────────────────────────────────
//  Promemoria lezione di prova (schedulato)
// ──────────────────────────────────────────────

Future<void> scheduleTrialReminder(String userId, String courseId) async {
  debugPrint('🔔 [scheduleTrialReminder] userId: $userId, courseId: $courseId');

  try {
    final firestore = FirebaseFirestore.instance;

    final courseQuery = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (courseQuery.docs.isEmpty) {
      debugPrint('🔔 [scheduleTrialReminder] Corso non trovato, skip');
      return;
    }

    final courseData = courseQuery.docs.first.data();
    final DateTime startDate = (courseData['startDate'] as Timestamp).toDate();
    final DateTime endDate = (courseData['endDate'] as Timestamp).toDate();

    final String sendAfter;
    if (kDebugMode) {
      final DateTime debugSendAt = DateTime.now().add(const Duration(seconds: 30));
      sendAfter = debugSendAt.toUtc().toIso8601String();
      debugPrint('🔔 [scheduleTrialReminder] DEBUG: invio tra 30 secondi ($sendAfter)');
    } else {
      final DateTime sendAt = DateTime(startDate.year, startDate.month, startDate.day - 1, 19, 0);
      if (sendAt.isBefore(DateTime.now())) {
        debugPrint('🔔 [scheduleTrialReminder] Data invio già passata ($sendAt), skip');
        return;
      }
      sendAfter = sendAt.toUtc().toIso8601String();
      debugPrint('🔔 [scheduleTrialReminder] Schedulato per: $sendAfter');
    }

    final String courseDate = _formatCourseDate(startDate);
    final String courseTime = _formatCourseTime(startDate, endDate);
    final String name = courseData['name'] as String? ?? '';

    // Leggi le preferenze notifiche dell'utente
    final userDoc = await firestore.collection('users').doc(userId).get();
    final userData = userDoc.data();
    final bool pushEnabled = userData?['pushNotificationsEnabled'] as bool? ?? true;
    final bool emailEnabled = userData?['emailNotificationsEnabled'] as bool? ?? true;
    debugPrint('🔔 [scheduleTrialReminder] Preferenze utente — push: $pushEnabled, email: $emailEnabled');

    await Future.wait([
      if (pushEnabled)
        _sendOneSignalRequest('Trial Push Reminder', {
          'include_aliases': {'external_id': [userId]},
          'target_channel': 'push',
          'send_after': sendAfter,
          'headings': {'it': _testPrefix('Promemoria lezione di prova'), 'en': _testPrefix('Trial lesson reminder')},
          'contents': {
            'it': 'La tua lezione di prova "$name" è domani ($courseDate, $courseTime). Ti aspettiamo!',
            'en': 'Your trial lesson "$name" is tomorrow ($courseDate, $courseTime). See you there!',
          },
        }),
      if (emailEnabled)
        _sendOneSignalRequest('Trial Email Reminder', {
          'include_aliases': {'external_id': [userId]},
          'target_channel': 'email',
          'send_after': sendAfter,
          'email_subject': _testPrefix(trialReminderSubject(name)),
          'email_body': trialReminderBody(
            courseName: name,
            courseDate: courseDate,
            courseTime: courseTime,
          ),
        }),
    ]);
  } catch (e) {
    debugPrint('🔔 [scheduleTrialReminder] ERRORE: $e');
  }
}

// ──────────────────────────────────────────────
//  Notifiche waitlist (immediate)
// ──────────────────────────────────────────────

Future<void> notifyWaitlistUsers(String courseId, String courseName) async {
  debugPrint('🔔 [notifyWaitlistUsers] courseId: $courseId, courseName: $courseName');

  try {
    final firestore = FirebaseFirestore.instance;

    final courseQuery = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (courseQuery.docs.isEmpty) {
      debugPrint('🔔 [notifyWaitlistUsers] Corso non trovato, skip');
      return;
    }

    final courseData = courseQuery.docs.first.data();
    final List<dynamic> waitlist = courseData['waitlist'] ?? [];
    final int subscribed = courseData['subscribed'] as int? ?? 0;
    final int capacity = courseData['capacity'] as int? ?? 0;

    debugPrint('🔔 [notifyWaitlistUsers] waitlist: $waitlist, subscribed: $subscribed, capacity: $capacity');

    if (waitlist.isEmpty) {
      debugPrint('🔔 [notifyWaitlistUsers] Waitlist vuota, skip');
      return;
    }
    if (subscribed >= capacity) {
      debugPrint('🔔 [notifyWaitlistUsers] Corso ancora pieno ($subscribed >= $capacity), skip');
      return;
    }

    final int spotsAvailable = capacity - subscribed;
    final List<String> waitlistUserIds = waitlist.map((id) => id.toString()).toList();

    // Leggi le preferenze notifiche di ciascun utente in waitlist
    final usersSnapshot = await firestore
        .collection('users')
        .where('uid', whereIn: waitlistUserIds)
        .get();

    debugPrint('🔔 [notifyWaitlistUsers] Utenti trovati su Firestore: ${usersSnapshot.docs.length}/${waitlistUserIds.length}');

    final DateTime startDate = (courseData['startDate'] as Timestamp).toDate();
    final DateTime endDate = (courseData['endDate'] as Timestamp).toDate();

    final List<String> pushUserIds = [];
    final List<String> emailUserIds = [];
    final List<String> expiredUserIds = [];
    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final uid = data['uid'] as String;

      if (data['fineIscrizione'] != null) {
        final DateTime subscriptionEnd = (data['fineIscrizione'] as Timestamp).toDate();
        if (startDate.isAfter(subscriptionEnd)) {
          debugPrint('🔔 [notifyWaitlistUsers] Utente $uid ha abbonamento scaduto, rimozione dalla waitlist');
          expiredUserIds.add(uid);
          continue;
        }
      }

      if (data['pushNotificationsEnabled'] as bool? ?? true) {
        pushUserIds.add(uid);
      }
      if (data['emailNotificationsEnabled'] as bool? ?? true) {
        emailUserIds.add(uid);
      }
    }

    debugPrint('🔔 [notifyWaitlistUsers] push: $pushUserIds, email: $emailUserIds, expired: $expiredUserIds');

    // Rimuovi gli utenti con abbonamento scaduto dalla waitlist
    if (expiredUserIds.isNotEmpty) {
      final courseRef = courseQuery.docs.first.reference;
      final WriteBatch batch = firestore.batch();
      batch.update(courseRef, {
        'waitlist': FieldValue.arrayRemove(expiredUserIds),
      });
      for (final uid in expiredUserIds) {
        final userRef = firestore.collection('users').doc(uid);
        batch.update(userRef, {
          'waitlistCourses': FieldValue.arrayRemove([courseId]),
        });
      }
      await batch.commit();
      debugPrint('🔔 [notifyWaitlistUsers] Rimossi ${expiredUserIds.length} utenti scaduti dalla waitlist');
    }

    final String courseDate = _formatCourseDate(startDate);
    final String courseTime = _formatCourseTime(startDate, endDate);
    final String name = courseData['name'] as String? ?? courseName;

    await Future.wait([
      if (pushUserIds.isNotEmpty)
        _sendOneSignalRequest('Waitlist Push', {
          'include_aliases': {'external_id': pushUserIds},
          'target_channel': 'push',
          'headings': {'it': _testPrefix('Posto disponibile!'), 'en': _testPrefix('Spot available!')},
          'contents': {
            'it': 'Si è liberato un posto nel corso "$name" ($courseDate, $courseTime). Iscriviti subito!',
            'en': 'A spot opened up in "$name" ($courseDate, $courseTime). Subscribe now!',
          },
        }),
      if (emailUserIds.isNotEmpty)
        _sendOneSignalRequest('Waitlist Email', {
          'include_aliases': {'external_id': emailUserIds},
          'target_channel': 'email',
          'email_subject': _testPrefix(waitlistSpotAvailableSubject(name)),
          'email_body': waitlistSpotAvailableBody(
            courseName: name,
            courseDate: courseDate,
            courseTime: courseTime,
            spotsAvailable: spotsAvailable,
          ),
        }),
    ]);
  } catch (e) {
    debugPrint('🔔 [notifyWaitlistUsers] ERRORE: $e');
  }
}
