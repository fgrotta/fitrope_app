import 'package:fitrope_app/types/course.dart';

String getCourseTimeRange(Course course) {
  DateTime startDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);
  DateTime endDate = DateTime.fromMillisecondsSinceEpoch(course.endDate.millisecondsSinceEpoch);

  return "${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')} - ${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}";
}