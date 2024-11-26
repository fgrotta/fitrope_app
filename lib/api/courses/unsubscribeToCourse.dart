import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> unsubscribeToCourse(String courseId, String userId) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('id', isEqualTo: courseId)
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

      if (userCourses.contains(courseId)) {
        userCourses.remove(courseId);

        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] + 1
        });
      }
    } else {
      throw Exception('No users subscribed to this course');
    }
  }).then((_) async {
    Map<String, dynamic>? userData = await getUserData(userId);
    if (userData != null) {
      store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      store.dispatch(FinishLoadingAction());
    }
  }).catchError((error) {
    print("Failed to unsubscribe: $error");
  });
}
