import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

Future<void> createCourse(Course course) async {
  try {
    CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');
    
    // Se l'id non è presente, genera un id univoco
    String courseId = course.id;
    if (courseId.isEmpty) {
      courseId = postsRef.doc().id;
    }
    
    // Crea il corso con l'id specificato
    await postsRef.doc(courseId).set(course.toJson());

    print('Course created successfully with ID: $courseId');
  } catch (e) {
    print('Error creating course: $e');
  }
}