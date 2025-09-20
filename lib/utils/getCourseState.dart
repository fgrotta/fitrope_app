import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int today = DateTime.now().millisecondsSinceEpoch;
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if(today > courseDay) {
    return CourseState.EXPIRED;
  }

  // Usa course.uid per la verifica dell'iscrizione (più affidabile)
  if(user.courses.contains(course.uid)) {
    return CourseState.SUBSCRIBED;
  }

  if(course.capacity <= course.subscribed) {
    return CourseState.FULL;
  }

  // Definisce courseDate per i controlli di scadenza
  DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courseDay);
    // Controlla prima se l'abbonamento è scaduto
  if((user.fineIscrizione != null && courseDate.isAfter(user.fineIscrizione!.toDate()))|| user.entrateSettimanali == null) {
      return CourseState.NULL;
  }
  if((user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA || user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE) 
      && (user.entrateDisponibili ?? 0) > 0) {
      return CourseState.CAN_SUBSCRIBE;
  }
  
  if(
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE
  ) {
    List<Course> allCourses = store.state.allCourses;
    List<Course> allSubscribedCourse = [];

    for(int n=0;n<user.courses.length;n++) {
      Course? course = allCourses.where((Course course) => course.uid == user.courses[n]).firstOrNull;
      if(course != null) {
        allSubscribedCourse.add(course);
      }
    }

    int subscriptionCounter = 0;

    DateTime startOfWeek = courseDate.subtract(Duration(days: courseDate.weekday - 1)).toUtc();
    startOfWeek = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
    int startOfWeekMillis = startOfWeek.millisecondsSinceEpoch;
    int endOfWeekMillis = endOfWeek.millisecondsSinceEpoch;

    for(int n=0;n<allSubscribedCourse.length;n++) {
      int courseStart = allSubscribedCourse[n].startDate.millisecondsSinceEpoch;
      bool isWithinCourseWeek = courseStart >= startOfWeekMillis && courseStart <= endOfWeekMillis;

      if(isWithinCourseWeek) {
        subscriptionCounter += 1;
      }
    }

    if(subscriptionCounter >= user.entrateSettimanali!) {
      return CourseState.NULL;
    }

    return CourseState.CAN_SUBSCRIBE;
  }

  return CourseState.NULL;
}