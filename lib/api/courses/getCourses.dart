import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

Future<List<Course>> getCourses(int gymId) async {
  CollectionReference collectionRef = FirebaseFirestore.instance.collection('courses');
  QuerySnapshot querySnapshot = await collectionRef.where('gymId', isEqualTo: gymId).get();

  List<Course> courses = [];

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    Course course = Course.fromJson(doc.data() as Map<String, dynamic>);
    courses.add(course);
  }

  return courses;
}

Future<List<Course>> getAllCourses() async {
  CollectionReference collectionRef = FirebaseFirestore.instance.collection('courses');
  QuerySnapshot querySnapshot = await collectionRef.get();

  List<Course> courses = [];

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    Course course = Course.fromJson(doc.data() as Map<String, dynamic>);
    courses.add(course);
  }

  return courses;
}