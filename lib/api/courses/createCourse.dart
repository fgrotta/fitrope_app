import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<Course?> createCourse(Course course) async {
  try {
    CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');
    
    // Se l'id non è presente, genera un id univoco
    if (course.uid.isEmpty) {
      var newID = postsRef.doc().id;
      // Serializza l'intero modello e sovrascrivi solo gli id, così nessun
      // campo (courseType, imageKey, waitlist, reminderEnabled, ...) viene
      // perso quando se ne aggiungono di nuovi al modello Course.
      final data = course.toJson()
        ..['uid'] = newID
        ..['id'] = newID;
      await postsRef.doc(newID).set(data);
      invalidateCoursesCache(); // Invalida la cache dopo la creazione

      print('Course created successfully with ID: $newID');
      return Course.fromJson(data);
    } else {
      print('Course already exists');
      return null;
    }  
  } catch (e) {
    print('Error creating course: $e');
    return null;
  }
}