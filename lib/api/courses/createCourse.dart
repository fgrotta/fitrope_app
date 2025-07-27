import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<Course?> createCourse(Course course) async {
  try {
    CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');
    
    // Se l'id non è presente, genera un id univoco
    if (course.id.isEmpty) {
      Course newCourse = new Course(name: course.name, startDate: course.startDate, endDate: course.endDate, id: postsRef.doc().id, capacity: course.capacity, subscribed: course.subscribed);
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