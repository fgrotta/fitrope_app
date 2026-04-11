import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:fitrope_app/main.dart' show oneSignalAppId;
import 'package:fitrope_app/services/email_templates.dart';

// TODO: Sostituire con la tua OneSignal REST API Key dalla dashboard
const String _oneSignalRestApiKey = 'YOUR_ONESIGNAL_REST_API_KEY';

const List<String> _dayNames = [
  'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'
];

const List<String> _monthNames = [
  'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
  'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
];

/// Programma un promemoria per una lezione di prova.
/// Invia push + email la sera prima del corso (ore 19:00).
///
/// Questa funzione è fire-and-forget: gestisce gli errori silenziosamente.
Future<void> scheduleTrialReminder(String userId, String courseId) async {
  try {
    final firestore = FirebaseFirestore.instance;

    final courseQuery = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (courseQuery.docs.isEmpty) return;

    final courseData = courseQuery.docs.first.data();

    final Timestamp startTimestamp = courseData['startDate'] as Timestamp;
    final Timestamp endTimestamp = courseData['endDate'] as Timestamp;
    final DateTime startDate = startTimestamp.toDate();
    final DateTime endDate = endTimestamp.toDate();

    // Calcola quando inviare: la sera prima alle 19:00
    final DateTime sendAt = DateTime(
      startDate.year,
      startDate.month,
      startDate.day - 1,
      19,
      0,
    );

    // Se la data di invio è già passata, non schedulare
    if (sendAt.isBefore(DateTime.now())) return;

    final String sendAfter = sendAt.toUtc().toIso8601String();

    final String courseDate =
        '${_dayNames[startDate.weekday - 1]} ${startDate.day} ${_monthNames[startDate.month - 1]} ${startDate.year}';
    final String courseTime =
        '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}'
        ' - '
        '${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}';

    final String name = courseData['name'] as String? ?? '';

    // Leggi le preferenze notifiche dell'utente
    final userDoc = await firestore.collection('users').doc(userId).get();
    final userData = userDoc.data();
    final bool pushEnabled = userData?['pushNotificationsEnabled'] as bool? ?? true;
    final bool emailEnabled = userData?['emailNotificationsEnabled'] as bool? ?? true;

    await Future.wait([
      if (pushEnabled)
        _sendScheduledPushReminder([userId], name, courseDate, courseTime, sendAfter),
      if (emailEnabled)
        _sendScheduledEmailReminder([userId], name, courseDate, courseTime, sendAfter),
    ]);
  } catch (e) {
    print('NotificationService: errore nella programmazione del promemoria: $e');
  }
}

Future<void> _sendScheduledPushReminder(
  List<String> userIds,
  String courseName,
  String courseDate,
  String courseTime,
  String sendAfter,
) async {
  try {
    final response = await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      },
      body: jsonEncode({
        'app_id': oneSignalAppId,
        'include_external_user_ids': userIds,
        'send_after': sendAfter,
        'headings': {'it': 'Promemoria lezione di prova', 'en': 'Trial lesson reminder'},
        'contents': {
          'it':
              'La tua lezione di prova "$courseName" è domani ($courseDate, $courseTime). Ti aspettiamo!',
          'en':
              'Your trial lesson "$courseName" is tomorrow ($courseDate, $courseTime). See you there!',
        },
        'url': appUrl,
      }),
    );

    if (response.statusCode == 200) {
      print('NotificationService: push promemoria programmata con successo');
    } else {
      print('NotificationService: errore push promemoria (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('NotificationService: errore invio push promemoria: $e');
  }
}

Future<void> _sendScheduledEmailReminder(
  List<String> userIds,
  String courseName,
  String courseDate,
  String courseTime,
  String sendAfter,
) async {
  try {
    final response = await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      },
      body: jsonEncode({
        'app_id': oneSignalAppId,
        'include_external_user_ids': userIds,
        'target_channel': 'email',
        'send_after': sendAfter,
        'email_subject': trialReminderSubject(courseName),
        'email_body': trialReminderBody(
          courseName: courseName,
          courseDate: courseDate,
          courseTime: courseTime,
        ),
      }),
    );

    if (response.statusCode == 200) {
      print('NotificationService: email promemoria programmata con successo');
    } else {
      print('NotificationService: errore email promemoria (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('NotificationService: errore invio email promemoria: $e');
  }
}

/// Notifica gli utenti in lista d'attesa che si e liberato un posto.
/// Invia sia push notification che email tramite OneSignal.
///
/// La notifica viene inviata solo se:
/// - La waitlist del corso non e vuota
/// - Il corso ha posti disponibili (subscribed < capacity)
///
/// Questa funzione e fire-and-forget: gestisce gli errori silenziosamente.
Future<void> notifyWaitlistUsers(String courseId, String courseName) async {
  try {
    final firestore = FirebaseFirestore.instance;

    final courseQuery = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (courseQuery.docs.isEmpty) return;

    final courseData = courseQuery.docs.first.data();
    final List<dynamic> waitlist = courseData['waitlist'] ?? [];
    final int subscribed = courseData['subscribed'] as int? ?? 0;
    final int capacity = courseData['capacity'] as int? ?? 0;

    if (waitlist.isEmpty) return;
    if (subscribed >= capacity) return;

    final int spotsAvailable = capacity - subscribed;
    final List<String> waitlistUserIds =
        waitlist.map((id) => id.toString()).toList();

    // Leggi le preferenze notifiche di ciascun utente in waitlist
    final usersSnapshot = await firestore
        .collection('users')
        .where('uid', whereIn: waitlistUserIds)
        .get();

    final List<String> pushUserIds = [];
    final List<String> emailUserIds = [];
    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final uid = data['uid'] as String;
      if (data['pushNotificationsEnabled'] as bool? ?? true) {
        pushUserIds.add(uid);
      }
      if (data['emailNotificationsEnabled'] as bool? ?? true) {
        emailUserIds.add(uid);
      }
    }

    final Timestamp startTimestamp = courseData['startDate'] as Timestamp;
    final Timestamp endTimestamp = courseData['endDate'] as Timestamp;
    final DateTime startDate = startTimestamp.toDate();
    final DateTime endDate = endTimestamp.toDate();

    final String courseDate =
        '${_dayNames[startDate.weekday - 1]} ${startDate.day} ${_monthNames[startDate.month - 1]} ${startDate.year}';
    final String courseTime =
        '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}'
        ' - '
        '${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}';

    final String name = courseData['name'] as String? ?? courseName;

    await Future.wait([
      if (pushUserIds.isNotEmpty)
        _sendPushNotification(pushUserIds, name, courseDate, courseTime),
      if (emailUserIds.isNotEmpty)
        _sendEmailNotification(
          emailUserIds,
          name,
          courseDate,
          courseTime,
          spotsAvailable,
        ),
    ]);
  } catch (e) {
    print('NotificationService: errore nell\'invio notifiche waitlist: $e');
  }
}

Future<void> _sendPushNotification(
  List<String> userIds,
  String courseName,
  String courseDate,
  String courseTime,
) async {
  try {
    final response = await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      },
      body: jsonEncode({
        'app_id': oneSignalAppId,
        'include_external_user_ids': userIds,
        'headings': {'it': 'Posto disponibile!', 'en': 'Spot available!'},
        'contents': {
          'it':
              'Si è liberato un posto nel corso "$courseName" ($courseDate, $courseTime). Iscriviti subito!',
          'en':
              'A spot opened up in "$courseName" ($courseDate, $courseTime). Subscribe now!',
        },
        'url': appUrl,
      }),
    );

    if (response.statusCode == 200) {
      print('NotificationService: push notification inviata con successo');
    } else {
      print(
          'NotificationService: errore push (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('NotificationService: errore invio push: $e');
  }
}

Future<void> _sendEmailNotification(
  List<String> userIds,
  String courseName,
  String courseDate,
  String courseTime,
  int spotsAvailable,
) async {
  try {
    final response = await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Basic $_oneSignalRestApiKey',
      },
      body: jsonEncode({
        'app_id': oneSignalAppId,
        'include_external_user_ids': userIds,
        'target_channel': 'email',
        'email_subject': waitlistSpotAvailableSubject(courseName),
        'email_body': waitlistSpotAvailableBody(
          courseName: courseName,
          courseDate: courseDate,
          courseTime: courseTime,
          spotsAvailable: spotsAvailable,
        ),
      }),
    );

    if (response.statusCode == 200) {
      print('NotificationService: email inviata con successo');
    } else {
      print(
          'NotificationService: errore email (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('NotificationService: errore invio email: $e');
  }
}
