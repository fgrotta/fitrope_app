import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/week_utils.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int today = DateTime.now().millisecondsSinceEpoch;
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if(today > courseDay) {
    return CourseState.EXPIRED;
  }

  if(user.courses.contains(course.id)) {
    return CourseState.SUBSCRIBED;
  }

  if(course.capacity <= course.subscribed) {
    return CourseState.FULL;
  }

  if(user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE && (user.entrateDisponibili ?? 0) > 0) {
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
      Course? course = allCourses.where((Course course) => course.id == user.courses[n]).firstOrNull;

      if(course != null) {
        allSubscribedCourse.add(course);
      }
    }

    int subscriptionCounter = 0;

    DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courseDay);
    String weekKey = WeekUtils.getWeekKey(courseDate);
    
    // Conta le iscrizioni attive per la settimana
    for(int n=0;n<allSubscribedCourse.length;n++) {
      int courseStart = allSubscribedCourse[n].startDate.millisecondsSinceEpoch;
      DateTime subscribedCourseDate = DateTime.fromMillisecondsSinceEpoch(courseStart);
      
      if(WeekUtils.isDateInWeek(subscribedCourseDate, weekKey)) {
        subscriptionCounter += 1;
      }
    }

    // Aggiungi le disdette tardive al conteggio per gli abbonamenti con limiti settimanali
    if(user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
       user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
       user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE) {
      
      int disdetteTardive = WeekUtils.getDisdetteTardiveForWeek(user.disdetteTardiveSettimanali, weekKey);
      subscriptionCounter += disdetteTardive;
    }

    if(user.entrateSettimanali == null) {
      return CourseState.NULL;
    }

    if(subscriptionCounter >= user.entrateSettimanali!) {
      return CourseState.NULL;
    }

    if(
      user.fineIscrizione != null && 
      today > user.fineIscrizione!.toDate().millisecondsSinceEpoch
    ) {
      return CourseState.NULL;
    }

    return CourseState.CAN_SUBSCRIBE;
  }

  return CourseState.NULL;
}