import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

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
      List<dynamic> subscribers = courseSnapshot['subscribers'] ?? [];
      if (subscribers.contains(userId)) {
        subscribers.remove(userId);
      }
      transaction.update(courseRef, {
        'subscribed': subscribed - 1,
        'subscribers': subscribers,
      });

      DocumentReference userRef = firestore.collection('users').doc(userId);

      DocumentSnapshot userSnapshot = await userRef.get();

      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      DateTime endDate = store.state.allCourses.where((Course course) => course.id == courseId).first.endDate.toDate();

      Duration difference = endDate.difference(DateTime.now());

      int hoursDifference = difference.inHours;


      if (userCourses.contains(courseId)) {
        userCourses.remove(courseId);

        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] + (hoursDifference > 12 ? 1 : 0)
        });
      }
    } else {
      throw Exception('No users subscribed to this course');
    }
  }).then((_) async {
    invalidateCoursesCache(); // Invalida la cache dopo la disiscrizione
    Map<String, dynamic>? userData = await getUserData(userId);
    if (userData != null) {
      store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      store.dispatch(FinishLoadingAction());
    }
  }).catchError((error) {
    print("Failed to unsubscribe: $error");
  });
}
