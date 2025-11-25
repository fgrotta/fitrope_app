import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<Course?> createCourse(Course course) async {
  try {
    CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');
    
    // Se l'uid non è presente, genera un uid univoco
    if (course.uid.isEmpty) {
      var newID = postsRef.doc().id;
      Course newCourse = Course(
        uid: newID,
        name: course.name, 
        startDate: course.startDate, 
        endDate: course.endDate, 
        capacity: course.capacity, 
        subscribed: course.subscribed,
        trainerId: course.trainerId,
        tags: course.tags,
      );
      await postsRef.doc(newCourse.uid).set(newCourse.toJson());
      invalidateCoursesCache(); // Invalida la cache dopo la creazione
      
      print('Course created successfully with UID: ${newCourse.uid}');
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