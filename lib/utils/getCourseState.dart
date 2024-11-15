import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int today = DateTime.now().millisecondsSinceEpoch;
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if(today > courseDay) {
    return CourseState.CANT_SUBSCRIBE;
  }

  if(course.capacity <= course.subscribed) {
    return CourseState.CANT_SUBSCRIBE;
  }

  // se un utente con abbonamento si è già prenotato ad un altro corso durante quella settimana CANT_SUBSCRIBE

  // se l'utente ha un abbonamento ad entrate allora può iscriversi

  return CourseState.CAN_SUBSCRIBE;
}