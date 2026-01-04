import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_tags.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if(DateTime.now().millisecondsSinceEpoch > courseDay) {
    return CourseState.CLOSED;// Corso passato
  }

  // Definisce courseDate per i controlli di scadenza
  DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courseDay);
  // Controlla prima se l'abbonamento è scaduto
  if((user.fineIscrizione != null && courseDate.isAfter(user.fineIscrizione!.toDate()))) {
      return CourseState.EXPIRED;
  }
  // Verifica se l'utente può accedere al corso basandosi sui tag
  if (!CourseTags.canUserAccessCourse(user.tipologiaCorsoTags, course.tags)) {
    return CourseState.NULL;
  }
  // Usa course.uid per la verifica dell'iscrizione (più affidabile)
  if(user.courses.contains(course.uid)) {
    return CourseState.SUBSCRIBED;// Utente iscritto al corso
  }

  if(course.capacity <= course.subscribed) {
    return CourseState.FULL;// Corso pieno
  }
  
  if((user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA || user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE)){
   if ((user.entrateDisponibili != null && user.entrateDisponibili! > 0)) {
      return CourseState.CAN_SUBSCRIBE;
    }  
   if(user.entrateDisponibili == 0 || user.entrateDisponibili == null) {
    return CourseState.SUBSCRIBE_LIMIT;// Prenotazioni esaurite
    }
  } 
  
  if(
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
    user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE
  ) {
    int weeklyEntriesUsed = _countWeeklyEntries(courseDate, user);
    
    if(weeklyEntriesUsed >= user.entrateSettimanali!) {
      return CourseState.LIMIT;
    }

    return CourseState.CAN_SUBSCRIBE;
  }

  return CourseState.NULL;
}

/// Conta gli ingressi settimanali usati considerando corsi attivi e disiscrizioni perse
/// 
/// [courseDate] - La data del corso per calcolare la settimana
/// [user] - L'utente di cui contare gli ingressi
/// 
/// Restituisce il numero di ingressi settimanali usati (corsi attivi + disiscrizioni perse)
/// Le disiscrizioni perse (entryLost: true) contano come ingressi usati perché l'ingresso è stato perso
int _countWeeklyEntries(DateTime courseDate, FitropeUser user) {
  List<Course> allCourses = store.state.allCourses;
  List<Course> allSubscribedCourse = [];

  // Trova tutti i corsi a cui l'utente è iscritto
  for(int n=0;n<user.courses.length;n++) {
    Course? course = allCourses.where((Course course) => course.uid == user.courses[n]).firstOrNull;
    if(course != null) {
      allSubscribedCourse.add(course);
    }
  }

  // Calcola l'inizio e la fine della settimana del corso
  DateTime startOfWeek = courseDate.subtract(Duration(days: courseDate.weekday - 1)).toUtc();
  startOfWeek = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
  int startOfWeekMillis = startOfWeek.millisecondsSinceEpoch;
  int endOfWeekMillis = endOfWeek.millisecondsSinceEpoch;

  // Conta i corsi attivi nella settimana
  int activeCoursesCount = 0;
  for(int n=0;n<allSubscribedCourse.length;n++) {
    int courseStart = allSubscribedCourse[n].startDate.millisecondsSinceEpoch;
    bool isWithinCourseWeek = courseStart >= startOfWeekMillis && courseStart <= endOfWeekMillis;

    if(isWithinCourseWeek) {
      activeCoursesCount += 1;
    }
  }

  // Conta le disiscrizioni perse nella stessa settimana
  // Le disiscrizioni perse (entryLost: true) contano come ingressi usati
  int lostEntriesCount = 0;
  for(var cancelled in user.cancelledEnrollments) {
    if (cancelled.entryLost) {
      DateTime cancelledCourseDate = cancelled.courseStartDate.toDate();
      int cancelledCourseStart = cancelledCourseDate.millisecondsSinceEpoch;
      bool isWithinCourseWeek = cancelledCourseStart >= startOfWeekMillis && cancelledCourseStart <= endOfWeekMillis;
      
      if(isWithinCourseWeek) {
        lostEntriesCount += 1;
      }
    }
  }
  
  // Gli ingressi usati = corsi attivi + disiscrizioni perse
  // Esempio: se un utente ha 2 ingressi settimanali, è iscritto a 1 corso e ha 1 disiscrizione persa,
  // allora ha usato 2 ingressi (1 attivo + 1 perso), quindi non può iscriversi ad altri corsi
  int weeklyEntriesUsed = activeCoursesCount + lostEntriesCount;
  
  return weeklyEntriesUsed;
}