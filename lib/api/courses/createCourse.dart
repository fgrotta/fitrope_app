import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

Future<void> createCourse(Course course) async {
    try {
      CollectionReference postsRef = FirebaseFirestore.instance.collection('courses');

      await postsRef.add(course.toJson());

      print('Course created successfully!');
    } catch (e) {
      print('Error creating course: $e');
    }
  }