import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/randomId.dart';

Future<void> createCoursesSet() async {
  Timestamp now = Timestamp.now();

  Timestamp oneDayLater = Timestamp.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch + const Duration(days: 1).inMilliseconds,
  );

  List<Future<void>> courses = [
    createCourse(Course(gymId: 1, name: 'Corso 1', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 2', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 3', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 4', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 20, subscribed: 5)),
    createCourse(Course(gymId: 1, name: 'Corso 5', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 20, subscribed: 5)),
  ];

  await Future.wait(courses);
}