import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

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
        throw Exception('User is already subscribed to this course');
      }

      if (userData['fineIscrizione'] != null) {
        DateTime subscriptionEnd = (userData['fineIscrizione'] as Timestamp).toDate();
        DateTime courseDate = (courseData['startDate'] as Timestamp).toDate();
        if (courseDate.isAfter(subscriptionEnd)) {
          throw Exception('Subscription has expired. Cannot subscribe to this course.');
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
        throw Exception('Course is full');
      }
    });

    invalidateUsersCache();
    final user = store.state.user;
    if (user != null && user.role != 'Admin' && user.role != 'Trainer') {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
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
