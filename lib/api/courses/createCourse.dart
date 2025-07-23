import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

Future<void> createCourse(Course course) async {
  try {
    CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');
    
    // Se l'id non è presente, genera un id univoco
    if (course.id.isEmpty) {
      Course newCourse = new Course(name: course.name, startDate: course.startDate, endDate: course.endDate, id: postsRef.doc().id, capacity: course.capacity, subscribed: course.subscribed);
      await postsRef.doc(newCourse.id).set(newCourse.toJson());
      print('Course created successfully with ID: ${newCourse.id}');
    } else { 
      print('Course already exists');
    }  
  } catch (e) {
    print('Error creating course: $e');
  }
}