import 'package:cloud_firestore/cloud_firestore.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> subscribeToCourse(String courseId, String userId) async {
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
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];
    int capacity = courseSnapshot['capacity'];

    if (subscribed < capacity) {
      transaction.update(courseRef, {
        'subscribed': subscribed + 1,
      });

      DocumentReference userRef = firestore.collection('users').doc(userId);

      DocumentSnapshot userSnapshot = await transaction.get(userRef);
      print('asd');
      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      if (!userCourses.contains(courseId)) {
        userCourses.add(courseId);

        transaction.update(userRef, {
          'courses': userCourses,
        });
      }
    } else {
      throw Exception('Course is full');
    }
  }).catchError((error) {
    print("Failed to subscribe: $error");
  });
}
