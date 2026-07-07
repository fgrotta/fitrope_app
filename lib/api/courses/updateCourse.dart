import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<void> updateCourse(Course course) async {
  try {
    await FirebaseFirestore.instance.collection('courses').doc(course.id).update(course.toJson());
    invalidateCoursesCache(); // Invalida la cache dopo l'aggiornamento
    debugPrint('Course updated ${course.id} successfully!');
  } catch (e) {
    debugPrint('Error updating course: $e');
  }
} 