import 'dart:math';

import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';

CourseState getCourseState(Course course, FitropeUser user) {
  int courseDay = course.startDate.millisecondsSinceEpoch;

  if (DateTime.now().millisecondsSinceEpoch > courseDay) {
    return CourseState.CLOSED; // Corso passato
  }

  // Già iscritto: è un FATTO, non l'esito di una valutazione di idoneità, quindi
  // precede scadenze e limiti. L'unica cosa che lo sovrascrive è il corso già
  // iniziato (CLOSED, sopra) — mirror del gate server, che sulla disiscrizione
  // self controlla solo "iscritto?" e "corso iniziato?" senza idoneità
  // (unsubscribeFromCourse in functions/src/enrollment/enrollment.ts).
  // Prima questo check stava dopo le scadenze: un iscritto con abbonamento
  // scaduto otteneva EXPIRED e CourseCard gli disabilitava il bottone, quindi
  // restava bloccato su un posto che non poteva liberare (e che il server gli
  // avrebbe lasciato liberare, con rimborso).
  if (user.courses.contains(course.uid)) {
    return CourseState.SUBSCRIBED;
  }

  DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courseDay);

  // Modello multi-abbonamento se lo snapshot contiene voci NON scadute;
  // altrimenti fallback al modello legacy (tipologiaIscrizione/entrate*/
  // fineIscrizione). Le voci scadute vengono scartate: lo snapshot viene
  // ricalcolato solo alle scritture (nessun cron di pulizia), quindi una voce
  // stantia non deve bloccare per sempre i crediti legacy dell'utente.
  // Mirror server: evaluateSubscribe in functions/src/enrollment/eligibility.ts.
  final DateTime now = DateTime.now();
  final List<UserSubscription> liveSubscriptions = user.activeSubscriptions
      .where((s) => !now.isAfter(s.endDate.toDate()))
      .toList();
  final bool useSubscriptions = liveSubscriptions.isNotEmpty;

  // Scadenza: solo legacy. Nel modello a abbonamenti è per-abbonamento ed è
  // valutata in _subscriptionGateState.
  if (!useSubscriptions &&
      (user.fineIscrizione == null ||
          courseDate.isAfter(user.fineIscrizione!.toDate()))) {
    return CourseState.EXPIRED;
  }

  final bool hasTagAccess = CourseTags.canUserAccessCourse(
    user.tipologiaCorsoTags,
    course.tags,
  );

  // Abbonamenti che coprono la tipologia del corso (solo modello multi-abbonamento).
  final List<UserSubscription> covering = useSubscriptions
      ? _coveringSubscriptions(course, liveSubscriptions)
      : const [];

  if (useSubscriptions &&
      covering.isNotEmpty &&
      !covering.any(
        (s) =>
            !courseDate.isBefore(s.startDate.toDate()) &&
            !courseDate.isAfter(s.endDate.toDate()),
      )) {
    return CourseState.EXPIRED;
  }

  // Accesso: legacy = solo tag; multi-abbonamento = tag OPPURE copertura
  // abbonamento (un abbonamento valido sblocca il corso anche se i tag legacy
  // non sono allineati, evitando falsi "Non disponibile").
  if (useSubscriptions) {
    if (!hasTagAccess && covering.isEmpty) return CourseState.NULL;
  } else if (!hasTagAccess) {
    return CourseState.NULL;
  }

  bool isInWaitlist = course.waitlist.contains(user.uid);
  bool courseFull = course.capacity <= course.subscribed;

  // Idoneità (crediti/limiti/scadenza) nello scope corretto.
  CourseState? limitState;
  if (useSubscriptions) {
    if (covering.isEmpty) {
      // Accessibile via tag ma nessun abbonamento copre la tipologia: se la
      // tipologia ha una famiglia (Open/Hyrox/PT) serve un abbonamento coprente
      // → non idoneo (NULL); se è una tipologia senza famiglia (es. Hey Mamma)
      // → nessun limite.
      final family = CourseTypes.byKey(_coursePrimaryTypeTag(course))?.family;
      limitState = family == null ? null : CourseState.NULL;
    } else {
      limitState = _evaluateCovering(covering, user, courseDate);
    }
  } else {
    limitState = _getSubscriptionLimitState(user, courseDate);
  }

  // Recupero nella giornata: un ingresso perso e non ancora assorbito ha già
  // pagato questa iscrizione, quindi il blocco per crediti esauriti non si
  // applica. Il limite settimanale invece è già nettato dentro
  // _countWeeklyEntries, quindi qui non va toccato.
  // Mirror server: evaluateSubscribe / countRecoverableEntries in eligibility.ts.
  if (limitState == CourseState.SUBSCRIBE_LIMIT &&
      recoverableEntriesOnDay(course, user) > 0) {
    limitState = null;
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

/// Tipologia "primaria" del corso: primo tag riconosciuto (o OPEN se nessuno).
/// Determina in modo DETERMINISTICO quale famiglia "consuma" il corso, così un
/// corso multi-tag non viene servito da più famiglie (no bypass di un limite).
String _coursePrimaryTypeTag(Course course) =>
    CourseTypes.primaryForTags(course.tags)?.key ?? CourseTags.OPEN;

/// Abbonamenti (tra quelli non scaduti) che coprono la tipologia primaria del corso.
List<UserSubscription> _coveringSubscriptions(
  Course course,
  List<UserSubscription> liveSubscriptions,
) {
  final String primary = _coursePrimaryTypeTag(course);
  return liveSubscriptions
      .where((s) => s.courseTypeTags.contains(primary))
      .toList();
}

/// Valuta scadenza + limiti nello scope degli abbonamenti che coprono il corso.
/// Precondizione: [covering] non vuoto. Ritorna null se l'utente è idoneo.
CourseState? _evaluateCovering(
  List<UserSubscription> covering,
  FitropeUser user,
  DateTime courseDate,
) {
  // Tieni solo gli abbonamenti validi alla data del corso: già iniziati
  // (startDate) e non ancora scaduti (endDate).
  final valid = covering
      .where(
        (s) =>
            !courseDate.isBefore(s.startDate.toDate()) &&
            !courseDate.isAfter(s.endDate.toDate()),
      )
      .toList();
  if (valid.isEmpty) return CourseState.EXPIRED;

  // Idoneo se ALMENO UN abbonamento valido consente l'iscrizione.
  for (final s in valid) {
    if (s.billingMode == BillingMode.ENTRIES) {
      if ((s.remainingEntries ?? 0) > 0) return null;
    } else {
      // FREQUENCY: null = illimitato.
      if (s.weeklyFrequency == null) return null;
      final used = _countWeeklyEntries(courseDate, user, s.courseTypeTags);
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
    int weeklyEntriesUsed = _countWeeklyEntries(courseDate, user, null);
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
  startOfWeek = DateTime.utc(
    startOfWeek.year,
    startOfWeek.month,
    startOfWeek.day,
  );
  DateTime endOfWeek = startOfWeek.add(
    const Duration(
      days: 6,
      hours: 23,
      minutes: 59,
      seconds: 59,
      milliseconds: 999,
    ),
  );
  return (
    start: startOfWeek.millisecondsSinceEpoch,
    end: endOfWeek.millisecondsSinceEpoch,
  );
}

/// Giorno civile (UTC) che contiene [millis]. Stessa convenzione del server
/// (`dayKeyMillis` in functions/src/enrollment/eligibility.ts): allineare i due
/// lati vale più che allineare il giorno locale dell'utente, e la palestra non
/// programma corsi fra mezzanotte e le 02:00.
int dayKeyMillis(int millis) => millis ~/ Duration.millisecondsPerDay;

void _bump(Map<int, int> counter, int key) =>
    counter[key] = (counter[key] ?? 0) + 1;

Course? _courseById(String? id) =>
    store.state.allCourses.where((c) => c.uid == id).firstOrNull;

/// Conta gli ingressi settimanali usati nella settimana di [courseDate].
///
/// REGOLA DI RECUPERO: un ingresso perso in una giornata è ASSORBITO, uno a uno,
/// da un'iscrizione attiva della stessa giornata (slot consumati in un giorno =
/// max(attive, persi), non attive + persi). Così chi disdice in ritardo e si
/// reiscrive a un corso dello stesso giorno non paga due volte, e se disdice
/// anche il rimpiazzo la penalità ritorna da sé.
///
/// Il corso CANDIDATO è incluso nel netting e poi sottratto: il chiamante
/// confronta il risultato con il limite SENZA contare il candidato, quindi senza
/// includerlo un utente al limite non potrebbe mai assorbire l'ingresso appena
/// perso. Senza ingressi persi il risultato è identico al conteggio precedente.
///
/// [typeTags] null = conteggio globale (modello legacy temporale); altrimenti
/// conta solo i corsi la cui tipologia primaria è in [typeTags].
///
/// Mirror di countWeeklyEntries in functions/src/enrollment/eligibility.ts.
int _countWeeklyEntries(
  DateTime courseDate,
  FitropeUser user,
  Set<String>? typeTags,
) {
  final bounds = _weekBoundsMillis(courseDate);
  bool matchesType(String? tag) =>
      typeTags == null || (tag != null && typeTags.contains(tag));

  final Map<int, int> activeByDay = {};
  _bump(activeByDay, dayKeyMillis(courseDate.millisecondsSinceEpoch));
  for (final id in user.courses) {
    final Course? course = _courseById(id);
    if (course == null) continue;
    final int start = course.startDate.millisecondsSinceEpoch;
    if (start < bounds.start || start > bounds.end) continue;
    if (!matchesType(_coursePrimaryTypeTag(course))) continue;
    _bump(activeByDay, dayKeyMillis(start));
  }

  final Map<int, int> lostByDay = {};
  int lostNotAbsorbable = 0;
  for (final cancelled in user.cancelledEnrollments) {
    if (!cancelled.entryLost) continue;
    // Una penalità su un INGRESSO non pesa sul limite settimanale (il credito
    // scalato è già la penalità): si recupera via [recoverableEntriesOnDay].
    if (cancelled.lostKindOrDefault == LostKind.ENTRY) continue;
    final int start = cancelled.courseStartDate.toDate().millisecondsSinceEpoch;
    if (start < bounds.start || start > bounds.end) continue;
    // Se il corso non è più risolvibile non possiamo determinarne la tipologia:
    // contiamo comunque l'ingresso perso (per non sotto-contare il limite) ma
    // non è assorbibile, perché non sappiamo a quale giornata-tipologia
    // appartenga. TODO(PR3): denormalizzare i tag in CancelledEnrollment.
    final Course? course = _courseById(cancelled.courseId);
    final String? tag = course == null ? null : _coursePrimaryTypeTag(course);
    if (typeTags == null || (tag != null && typeTags.contains(tag))) {
      _bump(lostByDay, dayKeyMillis(start));
    } else if (tag == null) {
      lostNotAbsorbable += 1;
    }
  }

  int total = lostNotAbsorbable;
  for (final day in {...activeByDay.keys, ...lostByDay.keys}) {
    total += max(activeByDay[day] ?? 0, lostByDay[day] ?? 0);
  }
  return total - 1;
}

/// Ingressi (crediti) persi nella giornata di [course] e non ancora assorbiti da
/// un'iscrizione attiva della stessa giornata e tipologia. > 0 significa che
/// l'iscrizione a [course] non scala credito: quell'ingresso è già stato pagato
/// dalla prenotazione disdetta in ritardo.
///
/// Mirror di countRecoverableEntries in functions/src/enrollment/eligibility.ts.
int recoverableEntriesOnDay(Course course, FitropeUser user) {
  final String primaryTag = _coursePrimaryTypeTag(course);
  final int day = dayKeyMillis(course.startDate.millisecondsSinceEpoch);

  int lost = 0;
  for (final cancelled in user.cancelledEnrollments) {
    if (!cancelled.entryLost) continue;
    if (cancelled.lostKindOrDefault != LostKind.ENTRY) continue;
    final int start = cancelled.courseStartDate.toDate().millisecondsSinceEpoch;
    if (dayKeyMillis(start) != day) continue;
    // Tipologia non risolvibile → non assorbibile: non regaliamo lezioni.
    final Course? origin = _courseById(cancelled.courseId);
    if (origin == null || _coursePrimaryTypeTag(origin) != primaryTag) continue;
    lost += 1;
  }
  if (lost == 0) return 0;

  int active = 0;
  for (final id in user.courses) {
    final Course? enrolled = _courseById(id);
    if (enrolled == null) continue;
    if (dayKeyMillis(enrolled.startDate.millisecondsSinceEpoch) == day &&
        _coursePrimaryTypeTag(enrolled) == primaryTag) {
      active += 1;
    }
  }
  return max(0, lost - active);
}
