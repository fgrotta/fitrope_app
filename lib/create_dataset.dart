import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/randomId.dart';

Future<void> createDataset() async {
  List<Future<void>> courses = [
    createCourse(Course(gymId: 1, name: 'Corso 1', startDate: Timestamp.now(), endDate: Timestamp.now(), id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 2', startDate: Timestamp.now(), endDate: Timestamp.now(), id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 3', startDate: Timestamp.now(), endDate: Timestamp.now(), id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 4', startDate: Timestamp.now(), endDate: Timestamp.now(), id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 5', startDate: Timestamp.now(), endDate: Timestamp.now(), id: randomId(), capacity: 20, subscribed: 5)),
  ];

  await Future.wait(courses);
}