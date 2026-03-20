import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

Future<void> leaveWaitlist(String courseId, String userId) async {
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

      List<dynamic> waitlist = List.from(courseData['waitlist'] ?? []);
      if (!waitlist.contains(userId)) {
        throw Exception('User is not in the waitlist');
      }

      waitlist.remove(userId);
      transaction.update(courseRef, {'waitlist': waitlist});

      DocumentReference userRef = firestore.collection('users').doc(userId);
      DocumentSnapshot userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw Exception('User document does not exist');
      }

      final userData = userSnapshot.data() as Map<String, dynamic>?;
      if (userData == null) {
        throw Exception('User data is null');
      }

      List<dynamic> waitlistCourses = List.from(userData['waitlistCourses'] ?? []);
      waitlistCourses.remove(courseId);
      transaction.update(userRef, {'waitlistCourses': waitlistCourses});
    });

    invalidateUsersCache();
    final currentUser = store.state.user;
    if (currentUser != null && currentUser.role != 'Admin' && currentUser.role != 'Trainer') {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }
  } catch (error, stackTrace) {
    print("Failed to leave waitlist: $error");
    print("Stack trace: $stackTrace");
    rethrow;
  } finally {
    store.dispatch(FinishLoadingAction());
  }
}
