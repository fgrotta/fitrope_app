import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> subscribeToCourse(String courseId, String userId,
    {bool force = false}) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('uid', isEqualTo: courseId)
      .limit(1)
      .get();

  if (querySnapshot.docs.isEmpty) {
    print('Course $courseId does not exist');
    throw Exception('Course $courseId does not exist');
  }

  DocumentReference courseRef = querySnapshot.docs.first.reference;

  await firestore.runTransaction((transaction) async {
    store.dispatch(StartLoadingAction());
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];
    int capacity = courseSnapshot['capacity'];
    if (subscribed < capacity || force) {
      transaction.update(courseRef, {
        'subscribed': subscribed + 1,
      });

      DocumentReference userRef = firestore.collection('users').doc(userId);

      // DocumentSnapshot userSnapshot = await transaction.get(userRef);
      DocumentSnapshot userSnapshot = await userRef.get();

      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      if (!userCourses.contains(courseId)) {
        userCourses.add(courseId);

        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] - 1
        });
      }
    } else {
      throw Exception('Course is full');
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
    print("Failed to subscribe: $error: ${error.toString()}");
  });
}
