import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/cleanCourses.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/randomId.dart';

void tests() async {
  Timestamp now = Timestamp.now();

  Timestamp oneDayLater = Timestamp.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch + const Duration(days: 1).inMilliseconds,
  );

  // cleanCourses();

  await createCourse(Course(gymId: 1, name: 'Corso FitRope 1', startDate: oneDayLater, endDate: oneDayLater, id: randomId(), capacity: 15, subscribed: 0));
}