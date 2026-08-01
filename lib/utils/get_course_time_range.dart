import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/italian_time.dart';

String getCourseTimeRange(Course course) {
  // Sempre orario italiano, a prescindere dal fuso del dispositivo.
  final startDate = toItalianTime(course.startDate.toDate());
  final endDate = toItalianTime(course.endDate.toDate());

  return "${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')} - ${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}";
}