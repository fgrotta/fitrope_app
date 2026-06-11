import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

// TODO(server-migration): portare createCourse in Cloud Function (piano §11,
// PR6+): finché resta client, il lockdown delle rules sui corsi è parziale.
Future<Course?> createCourse(Course course,
    {FirebaseFirestore? firestore}) async {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    CollectionReference postsRef = db.collection('courses');

    // Se l'id non è presente, genera un id univoco
    if (course.uid.isEmpty) {
      var newID = postsRef.doc().id;
      // copyWith preserva tutti i campi del corso (incl. reminderEnabled,
      // waitlistEnabled, sala) e sovrascrive solo l'id generato: evita il bug
      // della copia manuale che in passato scartava silenziosamente dei campi.
      Course newCourse = course.copyWith(uid: newID, id: newID);
      await postsRef.doc(newCourse.id).set(newCourse.toJson());
      invalidateCoursesCache(); // Invalida la cache dopo la creazione

      print('Course created successfully with ID: ${newCourse.id}');
      return newCourse;
    } else {
      print('Course already exists');
      return null;
    }
  } catch (e) {
    print('Error creating course: $e');
    return null;
  }
}
