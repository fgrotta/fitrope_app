import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';

/// Test sui casi limite di getCourseState e CourseUnsubscribeHelper.canUnsubscribe
/// che prima non avevano copertura:
/// - ABBONAMENTO_PROVA (trattato come PACCHETTO_ENTRATE ma non testato)
/// - tipologiaIscrizione null (fallback silenzioso)
/// - Tag incompatibili tra utente e corso (CourseState.NULL)
/// - Corso pieno con waitlistEnabled=false ma limiti raggiunti (deve tornare limit, non FULL)
/// - ABBONAMENTO temporale senza entrateSettimanali (nessun limite)
void main() {
  final now = DateTime.now();

  FitropeUser makeUser({
    String uid = 'user-1',
    TipologiaIscrizione? tipologia,
    int? entrateDisponibili,
    int? entrateSettimanali,
    Timestamp? fineIscrizione,
    List<String> courses = const [],
    List<String> tipologiaCorsoTags = const ['Tutti i corsi'],
    List<String> waitlistCourses = const [],
  }) {
    return FitropeUser(
      uid: uid,
      email: 'test@example.com',
      name: 'Test',
      lastName: 'User',
      courses: courses,
      tipologiaIscrizione: tipologia,
      entrateDisponibili: entrateDisponibili,
      entrateSettimanali: entrateSettimanali,
      fineIscrizione: fineIscrizione,
      role: 'User',
      createdAt: now,
      tipologiaCorsoTags: tipologiaCorsoTags,
      waitlistCourses: waitlistCourses,
    );
  }

  Course makeCourse({
    String uid = 'c1',
    int capacity = 10,
    int subscribed = 5,
    List<String> tags = const [],
    List<String> waitlist = const [],
    bool waitlistEnabled = true,
    DateTime? start,
  }) {
    final startDate = start ?? now.add(const Duration(days: 2));
    return Course(
      id: uid,
      uid: uid,
      name: 'Corso',
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(startDate.add(const Duration(hours: 1))),
      capacity: capacity,
      subscribed: subscribed,
      tags: tags,
      waitlist: waitlist,
      waitlistEnabled: waitlistEnabled,
    );
  }

  group('getCourseState - tipologiaIscrizione null', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('utente senza tipologiaIscrizione su corso disponibile -> NULL', () {
      final course = makeCourse();
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(tipologia: null);

      expect(getCourseState(course, user), CourseState.NULL);
    });

    test('utente senza tipologiaIscrizione su corso pieno -> NULL (limitState prevale)', () {
      final course = makeCourse(subscribed: 10);
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(tipologia: null);

      expect(getCourseState(course, user), CourseState.NULL);
    });
  });

  group('getCourseState - ABBONAMENTO_PROVA', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('ABBONAMENTO_PROVA con entrateDisponibili > 0 puo iscriversi', () {
      final course = makeCourse();
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
        entrateDisponibili: 1,
      );

      expect(getCourseState(course, user), CourseState.CAN_SUBSCRIBE);
    });

    test('ABBONAMENTO_PROVA senza crediti -> SUBSCRIBE_LIMIT', () {
      final course = makeCourse();
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
        entrateDisponibili: 0,
      );

      expect(getCourseState(course, user), CourseState.SUBSCRIBE_LIMIT);
    });

    test('ABBONAMENTO_PROVA con entrateDisponibili null -> SUBSCRIBE_LIMIT', () {
      final course = makeCourse();
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
      );

      expect(getCourseState(course, user), CourseState.SUBSCRIBE_LIMIT);
    });
  });

  group('getCourseState - tag incompatibili', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('utente OPEN non puo accedere a corso Personal Trainer -> NULL', () {
      final course = makeCourse(tags: [CourseTags.PERSONAL_TRAINER]);
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        tipologiaCorsoTags: [CourseTags.OPEN],
      );

      expect(getCourseState(course, user), CourseState.NULL);
    });

    test('il controllo tag avviene prima dell-iscrizione: utente gia iscritto con tag sbagliati -> NULL', () {
      final course = makeCourse(uid: 'c1', tags: [CourseTags.PERSONAL_TRAINER]);
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        tipologiaCorsoTags: [CourseTags.OPEN],
        courses: ['c1'],
      );

      expect(getCourseState(course, user), CourseState.NULL);
    });

    test('utente con "Tutti i corsi" bypassa i tag del corso', () {
      final course = makeCourse(tags: [CourseTags.PERSONAL_TRAINER]);
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        tipologiaCorsoTags: ['Tutti i corsi'],
      );

      expect(getCourseState(course, user), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('getCourseState - corso pieno + waitlistEnabled false + limiti raggiunti', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('corso pieno + waitlistEnabled false + pacchetto entrate senza crediti -> SUBSCRIBE_LIMIT', () {
      final course = makeCourse(subscribed: 10, waitlistEnabled: false);
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 0,
      );

      // Il limite ha la precedenza su FULL (l-utente non puo iscriversi comunque)
      expect(getCourseState(course, user), CourseState.SUBSCRIBE_LIMIT);
    });

    test('corso pieno + waitlistEnabled false + limite settimanale raggiunto -> LIMIT', () {
      final courseStart = now.add(const Duration(days: 2));
      final course = makeCourse(uid: 'c-full', subscribed: 10, waitlistEnabled: false, start: courseStart);
      final weekCourse = makeCourse(uid: 'c-already', start: courseStart.subtract(const Duration(hours: 1)));
      store.dispatch(SetAllCoursesAction([course, weekCourse]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 1,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        courses: ['c-already'],
      );

      expect(getCourseState(course, user), CourseState.LIMIT);
    });
  });

  group('getCourseState - abbonamento temporale senza entrateSettimanali', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('ABBONAMENTO_MENSILE con entrateSettimanali null -> nessun limite', () {
      final course = makeCourse();
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_ANNUALE,
        entrateSettimanali: null,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 300))),
      );

      expect(getCourseState(course, user), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('getCourseState - abbonamento scaduto precede tutti gli altri controlli', () {
    setUp(() => store.dispatch(SetAllCoursesAction([])));

    test('utente scaduto iscritto al corso -> EXPIRED (non SUBSCRIBED)', () {
      final course = makeCourse(
        uid: 'c1',
        start: now.add(const Duration(days: 10)),
      );
      store.dispatch(SetAllCoursesAction([course]));
      final user = makeUser(
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 5))),
        courses: ['c1'],
      );

      expect(getCourseState(course, user), CourseState.EXPIRED);
    });
  });

  group('CourseUnsubscribeHelper.canUnsubscribe - ABBONAMENTO_PROVA', () {
    test('ABBONAMENTO_PROVA > 8 ore: nessuna conferma richiesta, isPacchettoEntrate true', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 11))),
        capacity: 10, subscribed: 1,
      );
      final user = FitropeUser(
        uid: 'u1', email: 'x@y.z', name: 'N', lastName: 'L',
        courses: ['c1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_PROVA,
        entrateDisponibili: 1,
        role: 'User', createdAt: now,
      );

      final result = CourseUnsubscribeHelper.canUnsubscribe(course, user);

      expect(result['canUnsubscribe'], true);
      expect(result['requiresConfirmation'], false);
      expect(result['isPacchettoEntrate'], true,
          reason: 'ABBONAMENTO_PROVA viene raggruppato con PACCHETTO_ENTRATE');
      expect(result['message'], 'Disiscrizione: il credito ti sarà rimborsato');
    });

    test('ABBONAMENTO_PROVA <= 8 ore: conferma richiesta con messaggio "perderai il credito"', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 4))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 5))),
        capacity: 10, subscribed: 1,
      );
      final user = FitropeUser(
        uid: 'u1', email: 'x@y.z', name: 'N', lastName: 'L',
        courses: ['c1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_PROVA,
        entrateDisponibili: 1,
        role: 'User', createdAt: now,
      );

      final result = CourseUnsubscribeHelper.canUnsubscribe(course, user);

      expect(result['canUnsubscribe'], true);
      expect(result['requiresConfirmation'], true);
      expect(result['isPacchettoEntrate'], true);
      expect(result['message'], 'Disiscrizione a meno di 8 ore: perderai il credito');
    });
  });

  group('CourseUnsubscribeHelper.canUnsubscribe - tipologiaIscrizione null', () {
    test('utente senza tipologia: mai richiede conferma, messaggio generico "liberi il posto"', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 1))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 2))),
        capacity: 10, subscribed: 1,
      );
      final user = FitropeUser(
        uid: 'u1', email: 'x@y.z', name: 'N', lastName: 'L',
        courses: ['c1'],
        tipologiaIscrizione: null,
        role: 'User', createdAt: now,
      );

      final result = CourseUnsubscribeHelper.canUnsubscribe(course, user);

      expect(result['canUnsubscribe'], true);
      expect(result['requiresConfirmation'], false,
          reason: 'Senza tipologia non rientra in nessuna soglia: nessuna conferma');
      expect(result['isPacchettoEntrate'], false);
      expect(result['isTemporalSubscription'], false);
      expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
    });
  });

  group('CourseUnsubscribeHelper.canUnsubscribe - ABBONAMENTO temporale > 4 ore', () {
    test('ABBONAMENTO_TRIMESTRALE a 5 ore: nessuna conferma', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 5))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 6))),
        capacity: 10, subscribed: 1,
      );
      final user = FitropeUser(
        uid: 'u1', email: 'x@y.z', name: 'N', lastName: 'L',
        courses: ['c1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 60))),
        role: 'User', createdAt: now,
      );

      final result = CourseUnsubscribeHelper.canUnsubscribe(course, user);

      expect(result['requiresConfirmation'], false);
      expect(result['isTemporalSubscription'], true);
      expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
    });

    test('ABBONAMENTO_ANNUALE esattamente a 4 ore: conferma richiesta (soglia inclusiva)', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        // 4 ore esatte, + qualche secondo per robustezza cronometrica
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 4, seconds: 1))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 5))),
        capacity: 10, subscribed: 1,
      );
      final user = FitropeUser(
        uid: 'u1', email: 'x@y.z', name: 'N', lastName: 'L',
        courses: ['c1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_ANNUALE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 300))),
        role: 'User', createdAt: now,
      );

      final result = CourseUnsubscribeHelper.canUnsubscribe(course, user);

      expect(result['requiresConfirmation'], true);
      expect(result['isTemporalSubscription'], true);
      expect(result['message'], 'Disiscrizione a meno di 4 ore: perderai l\'ingresso settimanale');
    });
  });
}
