import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/services/notification_service.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<void> subscribeToCourse(String courseId, String userId, {bool force = false, String? userRole}) async {
  if (userRole == 'Admin' || userRole == 'Trainer') {
    throw Exception('Admin e Trainer non possono iscriversi ai corsi');
  }
  final firestore = FirebaseFirestore.instance;
  store.dispatch(StartLoadingAction());

  try {
    QuerySnapshot querySnapshot = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception('Course $courseId does not exist');
    }

    DocumentReference courseRef = querySnapshot.docs.first.reference;

    await firestore.runTransaction((transaction) async {
      DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
      if (!courseSnapshot.exists) {
        throw Exception('Course document no longer exists');
      }

      final courseData = courseSnapshot.data() as Map<String, dynamic>?;
      if (courseData == null) {
        throw Exception('Course data is null');
      }

      int subscribed = courseData['subscribed'] as int? ?? 0;
      int capacity = courseData['capacity'] as int? ?? 0;

      DocumentReference userRef = firestore.collection('users').doc(userId);
      DocumentSnapshot userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw Exception('User document does not exist');
      }

      final userData = userSnapshot.data() as Map<String, dynamic>?;
      if (userData == null) {
        throw Exception('User data is null');
      }

      List<dynamic> userCourses = userData['courses'] ?? [];

      if (userCourses.contains(courseId)) {
        throw Exception('L\'utente è già iscritto a questo corso.');
      }

      // I controlli su data di fine iscrizione valgono solo per l'iscrizione
      // self-service. Admin/Trainer (force) bypassano sia la data mancante sia
      // la scadenza, per poter aggiungere manualmente l'utente.
      if (!force) {
        if (userData['fineIscrizione'] == null) {
          throw Exception('Data di fine iscrizione non impostata. Contatta lo staff per attivare l\'abbonamento.');
        }
        DateTime subscriptionEnd = (userData['fineIscrizione'] as Timestamp).toDate();
        DateTime courseDate = (courseData['startDate'] as Timestamp).toDate();
        if (courseDate.isAfter(subscriptionEnd)) {
          throw Exception('Abbonamento scaduto: impossibile iscriversi a un corso successivo alla fine dell\'abbonamento.');
        }
      }

      if (subscribed < capacity || force) {
        Map<String, dynamic> courseUpdate = {'subscribed': subscribed + 1};

        List<dynamic> waitlist = List.from(courseData['waitlist'] ?? []);
        if (waitlist.contains(userId)) {
          waitlist.remove(userId);
          courseUpdate['waitlist'] = waitlist;
        }

        transaction.update(courseRef, courseUpdate);

        userCourses = List.from(userCourses);
        userCourses.add(courseId);
        int currentEntrate = (userData['entrateDisponibili'] as int?) ?? 0;
        Map<String, dynamic> userUpdate = {
          'courses': userCourses,
          'entrateDisponibili': currentEntrate - 1,
        };

        List<dynamic> waitlistCourses = List.from(userData['waitlistCourses'] ?? []);
        if (waitlistCourses.contains(courseId)) {
          waitlistCourses.remove(courseId);
          userUpdate['waitlistCourses'] = waitlistCourses;
        }

        transaction.update(userRef, userUpdate);
      } else {
        throw Exception('Il corso è al completo.');
      }
    });

    invalidateUsersCache();
    invalidateCoursesCache();
    final user = store.state.user;
    print('🔔 [subscribeToCourse] Iscrizione completata — userId: $userId, courseId: $courseId');
    print('🔔 [subscribeToCourse] Utente corrente nello store: uid=${user?.uid}, role=${user?.role}');

    if (user != null && user.role != 'Admin' && user.role != 'Trainer') {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        final updatedUser = FitropeUser.fromJson(userData);
        store.dispatch(SetUserAction(updatedUser));

        print('🔔 [subscribeToCourse] tipologiaIscrizione: ${updatedUser.tipologiaIscrizione}');
        if (kDebugMode || updatedUser.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA) {
          print('🔔 [subscribeToCourse] ${kDebugMode ? "[DEBUG] Invio sempre" : "Utente PROVA"} → scheduleTrialReminder');
          scheduleTrialReminder(userId, courseId);
        } else {
          print('🔔 [subscribeToCourse] Non è ABBONAMENTO_PROVA, skip promemoria');
        }
      } else {
        print('🔔 [subscribeToCourse] userData null per userId: $userId');
      }
    } else {
      print('🔔 [subscribeToCourse] Branch admin/trainer — controlla utente iscritto');
      Map<String, dynamic>? subscribedUserData = await getUserData(userId);
      if (subscribedUserData != null) {
        final subscribedUser = FitropeUser.fromJson(subscribedUserData);
        print('🔔 [subscribeToCourse] tipologiaIscrizione utente iscritto: ${subscribedUser.tipologiaIscrizione}');
        if (kDebugMode || subscribedUser.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA) {
          print('🔔 [subscribeToCourse] ${kDebugMode ? "[DEBUG] Invio sempre" : "Utente PROVA"} → scheduleTrialReminder');
          scheduleTrialReminder(userId, courseId);
        } else {
          print('🔔 [subscribeToCourse] Non è ABBONAMENTO_PROVA, skip promemoria');
        }
      } else {
        print('🔔 [subscribeToCourse] subscribedUserData null per userId: $userId');
      }
    }
  } catch (error, stackTrace) {
    print("Failed to subscribe to course: $error");
    print("Stack trace: $stackTrace");
    rethrow;
  } finally {
    store.dispatch(FinishLoadingAction());
  }
}
