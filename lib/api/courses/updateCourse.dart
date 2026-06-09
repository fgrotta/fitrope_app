import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<void> updateCourse(Course course, {FirebaseFirestore? firestore}) async {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    await db.collection('courses').doc(course.uid).update(course.toJson());
    invalidateCoursesCache(); // Invalida la cache dopo l'aggiornamento
    print('Course updated ${course.uid} successfully!');
  } catch (e) {
    print('Error updating course: $e');
  }
}
