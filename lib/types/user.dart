import 'package:fitrope_app/types/course.dart';

class User {
  final String uid;
  final String name;
  final String lastName;
  final List<Course> courses;

  const User({required this.name, required this.lastName, required this.uid, required this.courses});
}