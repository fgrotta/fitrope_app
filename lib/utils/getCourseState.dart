import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if (DateTime.now().millisecondsSinceEpoch > courseDay) {
    return CourseState.CLOSED; // Corso passato
  }

  DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courseDay);

  // Modello multi-abbonamento se è presente lo snapshot; altrimenti fallback
  // al modello legacy (campi tipologiaIscrizione/entrate*/fineIscrizione).
  final bool useSubscriptions = user.activeSubscriptions.isNotEmpty;

  // Scadenza: solo legacy. Nel modello a abbonamenti è per-abbonamento ed è
  // valutata in _subscriptionGateState.
  if (!useSubscriptions &&
      user.fineIscrizione != null &&
      courseDate.isAfter(user.fineIscrizione!.toDate())) {
    return CourseState.EXPIRED;
  }

  final bool hasTagAccess =
      CourseTags.canUserAccessCourse(user.tipologiaCorsoTags, course.tags);

  // Abbonamenti che coprono la tipologia del corso (solo modello multi-abbonamento).
  final List<UserSubscription> covering =
      useSubscriptions ? _coveringSubscriptions(course, user) : const [];

  // Accesso: legacy = solo tag; multi-abbonamento = tag OPPURE copertura
  // abbonamento (un abbonamento valido sblocca il corso anche se i tag legacy
  // non sono allineati, evitando falsi "Non disponibile").
  if (useSubscriptions) {
    if (!hasTagAccess && covering.isEmpty) return CourseState.NULL;
  } else if (!hasTagAccess) {
    return CourseState.NULL;
  }

  // Già iscritto (precede scadenza/limiti: se sei dentro, resti dentro).
  if (user.courses.contains(course.uid)) {
    return CourseState.SUBSCRIBED;
  }

  bool isInWaitlist = course.waitlist.contains(user.uid);
  bool courseFull = course.capacity <= course.subscribed;

  // Idoneità (crediti/limiti/scadenza) nello scope corretto. Nel modello
  // multi-abbonamento un corso accessibile via tag ma NON coperto da alcun
  // abbonamento (es. Hey Mamma, tipologia senza famiglia) non ha limiti.
  CourseState? limitState;
  if (useSubscriptions) {
    limitState =
        covering.isEmpty ? null : _evaluateCovering(covering, user, courseDate);
  } else {
    limitState = _getSubscriptionLimitState(user, courseDate);
  }

  if (courseFull) {
    // Se la waitlist è disabilitata per questo corso, non proporla.
    if (!course.waitlistEnabled) {
      if (limitState != null) return limitState;
      return CourseState.FULL;
    }
    if (isInWaitlist) return CourseState.IN_WAITLIST;
    if (limitState != null) return limitState;
    return CourseState.CAN_WAITLIST;
  }

  // Corso con posti disponibili.
  if (limitState != null) return limitState;
  if (isInWaitlist && course.waitlistEnabled) {
    return CourseState.WAITLIST_SPOT_AVAILABLE;
  }
  return CourseState.CAN_SUBSCRIBE;
}

/// Tag di tipologia effettivi del corso (un corso senza tag è trattato come OPEN).
/// Tipologia "primaria" del corso: primo tag riconosciuto (o OPEN se nessuno).
/// Determina in modo DETERMINISTICO quale famiglia "consuma" il corso, così un
/// corso multi-tag non viene servito da più famiglie (no bypass di un limite).
String _coursePrimaryTypeTag(Course course) =>
    CourseTypes.primaryForTags(course.tags)?.key ?? CourseTags.OPEN;

/// Abbonamenti dell'utente che coprono la tipologia primaria del corso.
List<UserSubscription> _coveringSubscriptions(Course course, FitropeUser user) {
  final String primary = _coursePrimaryTypeTag(course);
  return user.activeSubscriptions
      .where((s) => s.courseTypeTags.contains(primary))
      .toList();
}

/// Valuta scadenza + limiti nello scope degli abbonamenti che coprono il corso.
/// Precondizione: [covering] non vuoto. Ritorna null se l'utente è idoneo.
CourseState? _evaluateCovering(
    List<UserSubscription> covering, FitropeUser user, DateTime courseDate) {
  // Tieni solo gli abbonamenti validi alla data del corso: già iniziati
  // (startDate) e non ancora scaduti (endDate).
  final valid = covering
      .where((s) =>
          !courseDate.isBefore(s.startDate.toDate()) &&
          !courseDate.isAfter(s.endDate.toDate()))
      .toList();
  if (valid.isEmpty) return CourseState.EXPIRED;

  // Idoneo se ALMENO UN abbonamento valido consente l'iscrizione.
  for (final s in valid) {
    if (s.billingMode == BillingMode.ENTRIES) {
      if ((s.remainingEntries ?? 0) > 0) return null;
    } else {
      // FREQUENCY: null = illimitato.
      if (s.weeklyFrequency == null) return null;
      final used =
          _countWeeklyEntriesForTags(courseDate, user, s.courseTypeTags);
      if (used < s.weeklyFrequency!) return null;
    }
  }

  // Non idoneo: stato in base alla modalità (1:1 famiglia↔tipologia → stessa modalità).
  return valid.first.billingMode == BillingMode.ENTRIES
      ? CourseState.SUBSCRIBE_LIMIT
      : CourseState.LIMIT;
}

/// Restituisce lo stato limite se l'utente non può iscriversi per crediti/limiti,
/// oppure null se l'utente è idoneo. (Modello legacy mono-abbonamento.)
CourseState? _getSubscriptionLimitState(FitropeUser user, DateTime courseDate) {
  if (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA ||
      user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE) {
    if (user.entrateDisponibili != null && user.entrateDisponibili! > 0) {
      return null;
    }
    return CourseState.SUBSCRIBE_LIMIT;
  }

  if (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE) {
    if (user.entrateSettimanali == null) {
      return null; // nessun limite settimanale
    }
    int weeklyEntriesUsed = _countWeeklyEntries(courseDate, user);
    if (weeklyEntriesUsed >= user.entrateSettimanali!) {
      return CourseState.LIMIT;
    }
    return null;
  }

  return CourseState.NULL;
}

/// Inizio/fine (in millis) della settimana che contiene [courseDate] (lun-dom, UTC).
({int start, int end}) _weekBoundsMillis(DateTime courseDate) {
  DateTime startOfWeek =
      courseDate.subtract(Duration(days: courseDate.weekday - 1)).toUtc();
  startOfWeek =
      DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  DateTime endOfWeek = startOfWeek.add(const Duration(
      days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
  return (
    start: startOfWeek.millisecondsSinceEpoch,
    end: endOfWeek.millisecondsSinceEpoch
  );
}

/// Conta gli ingressi settimanali usati (corsi attivi + disiscrizioni perse) nel
/// modello legacy: tutti i corsi della settimana, senza distinzione di tipologia.
int _countWeeklyEntries(DateTime courseDate, FitropeUser user) {
  final bounds = _weekBoundsMillis(courseDate);
  final List<Course> allCourses = store.state.allCourses;

  int activeCoursesCount = 0;
  for (final id in user.courses) {
    final Course? course = allCourses.where((c) => c.uid == id).firstOrNull;
    if (course == null) continue;
    final int start = course.startDate.millisecondsSinceEpoch;
    if (start >= bounds.start && start <= bounds.end) activeCoursesCount += 1;
  }

  // Le disiscrizioni perse (entryLost: true) contano come ingressi usati.
  int lostEntriesCount = 0;
  for (final cancelled in user.cancelledEnrollments) {
    if (!cancelled.entryLost) continue;
    final int start = cancelled.courseStartDate.toDate().millisecondsSinceEpoch;
    if (start >= bounds.start && start <= bounds.end) lostEntriesCount += 1;
  }

  return activeCoursesCount + lostEntriesCount;
}

/// Come [_countWeeklyEntries], ma conta solo i corsi la cui tipologia rientra in
/// [typeTags] (scoping per famiglia, modello multi-abbonamento). Le disiscrizioni
/// perse contano solo se il corso originario è ancora risolvibile e della tipologia.
int _countWeeklyEntriesForTags(
    DateTime courseDate, FitropeUser user, Set<String> typeTags) {
  final bounds = _weekBoundsMillis(courseDate);
  final List<Course> allCourses = store.state.allCourses;

  bool matchesType(Course c) => typeTags.contains(_coursePrimaryTypeTag(c));

  int activeCoursesCount = 0;
  for (final id in user.courses) {
    final Course? course = allCourses.where((c) => c.uid == id).firstOrNull;
    if (course == null) continue;
    final int start = course.startDate.millisecondsSinceEpoch;
    if (start >= bounds.start && start <= bounds.end && matchesType(course)) {
      activeCoursesCount += 1;
    }
  }

  int lostEntriesCount = 0;
  for (final cancelled in user.cancelledEnrollments) {
    if (!cancelled.entryLost) continue;
    final int start = cancelled.courseStartDate.toDate().millisecondsSinceEpoch;
    if (start < bounds.start || start > bounds.end) continue;
    final Course? course =
        allCourses.where((c) => c.uid == cancelled.courseId).firstOrNull;
    // Se il corso non è più risolvibile non possiamo determinarne la tipologia:
    // contiamo comunque l'ingresso perso (come il modello legacy) per non
    // sotto-contare il limite. TODO(PR3): denormalizzare i tag in CancelledEnrollment.
    if (course == null || matchesType(course)) lostEntriesCount += 1;
  }

  return activeCoursesCount + lostEntriesCount;
}
