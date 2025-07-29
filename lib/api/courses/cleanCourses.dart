import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<void> cleanCourses() async {
  try {
    CollectionReference coursesRef = FirebaseFirestore.instance.collection('courses');

    QuerySnapshot snapshot = await coursesRef.get();

    // for (QueryDocumentSnapshot doc in snapshot.docs) {
    //   await doc.reference.delete();
    // }

    // await coursesRef.doc('placeholder').set({'info': 'This is a placeholder document'});
    invalidateCoursesCache(); // Invalida la cache dopo la pulizia

    print('Courses collection cleaned successfully, placeholder added!');
  } catch (e) {
    print('Error cleaning courses collection: $e');
  }
}