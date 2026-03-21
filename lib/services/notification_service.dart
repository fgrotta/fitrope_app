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
      _sendPushNotification(waitlistUserIds, name, courseDate, courseTime),
      _sendEmailNotification(
        waitlistUserIds,
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
