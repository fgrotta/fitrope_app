import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

class WaitlistRemovalResult {
  final List<dynamic> updatedCourseWaitlist;
  final List<dynamic> updatedUserWaitlistCourses;
  final bool removedFromCourse;
  final bool removedFromUser;

  const WaitlistRemovalResult({
    required this.updatedCourseWaitlist,
    required this.updatedUserWaitlistCourses,
    required this.removedFromCourse,
    required this.removedFromUser,
  });

  bool get hasChanges => removedFromCourse || removedFromUser;
}

WaitlistRemovalResult computeWaitlistRemoval({
  required List<dynamic> courseWaitlist,
  required List<dynamic> userWaitlistCourses,
  required String userId,
  required String courseId,
}) {
  final updatedCourseWaitlist = List<dynamic>.from(courseWaitlist);
  final updatedUserWaitlistCourses = List<dynamic>.from(userWaitlistCourses);

  final removedFromCourse = updatedCourseWaitlist.remove(userId);
  final removedFromUser = updatedUserWaitlistCourses.remove(courseId);

  return WaitlistRemovalResult(
    updatedCourseWaitlist: updatedCourseWaitlist,
    updatedUserWaitlistCourses: updatedUserWaitlistCourses,
    removedFromCourse: removedFromCourse,
    removedFromUser: removedFromUser,
  );
}

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

      final removalResult = computeWaitlistRemoval(
        courseWaitlist: waitlist,
        userWaitlistCourses: waitlistCourses,
        userId: userId,
        courseId: courseId,
      );

      if (!removalResult.hasChanges) {
        throw Exception('User is not in the waitlist');
      }

      if (removalResult.removedFromCourse) {
        transaction.update(courseRef, {
          'waitlist': removalResult.updatedCourseWaitlist,
        });
      }

      if (removalResult.removedFromUser) {
        transaction.update(userRef, {
          'waitlistCourses': removalResult.updatedUserWaitlistCourses,
        });
      }
    });

    invalidateUsersCache();
    invalidateCoursesCache();
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
