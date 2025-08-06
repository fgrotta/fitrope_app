import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> unsubscribeToCourse(String courseId, String userId, {bool userConfirmed = false}) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('uid', isEqualTo: courseId)
      .limit(1)
      .get();

  if (querySnapshot.docs.isEmpty) {
    throw Exception('Course does not exist');
  }

  DocumentReference courseRef = querySnapshot.docs.first.reference;

  await firestore.runTransaction((transaction) async {
    store.dispatch(StartLoadingAction());
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];

    if (subscribed > 0) {
      
      transaction.update(courseRef, {
        'subscribed': subscribed - 1,
      });

      DocumentReference userRef = firestore.collection('users').doc(userId);

      DocumentSnapshot userSnapshot = await userRef.get();

      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      DateTime startDate = courseSnapshot['startDate'].toDate();
      DateTime now = DateTime.now();

      Duration difference = startDate.difference(now);
      int hoursDifference = difference.inHours;

      // Controlla il tipo di abbonamento dell'utente
      String? tipologiaIscrizione = userSnapshot['tipologiaIscrizione'];
      bool isPacchettoEntrate = tipologiaIscrizione == 'PACCHETTO_ENTRATE';
      
      // Per il pacchetto entrate, controlla se la disiscrizione è nelle 8 ore precedenti
      bool shouldRefund = true;
      if (isPacchettoEntrate && hoursDifference <= 8) {
        if (!userConfirmed) {
          throw Exception('CONFIRMATION_REQUIRED');
        }
        shouldRefund = false;
      }

      if (userCourses.contains(courseId)) {
        userCourses.remove(courseId);

        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] + (shouldRefund ? 1 : 0)
        });
      }
    } else {
      print('No users subscribed to this course');
      throw Exception('No users subscribed to this course');
    }
  }).then((_) async {
    invalidateUsersCache();
    if (store.state.user!.uid == userId) {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }   
    store.dispatch(FinishLoadingAction());
  }).catchError((error) {
    store.dispatch(FinishLoadingAction());
    print("Failed to unsubscribe: $error");
    throw error;
  });
}
