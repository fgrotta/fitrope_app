import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_recovery.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/utils/get_course_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recupero nella giornata: una lezione persa per disdetta tardiva è assorbita
/// da un'iscrizione attiva della STESSA giornata e tipologia (uno a uno).
/// Mirror dei test server in functions/src/__tests__/eligibility.test.ts.
void main() {
  // Giornata di riferimento nel futuro (evita CourseState.CLOSED) e non oltre
  // mercoledì, così "giorno dopo" resta nella stessa settimana ISO.
  DateTime anchorDay() {
    final n = DateTime.now().toUtc().add(const Duration(days: 3));
    var day = DateTime.utc(n.year, n.month, n.day);
    while (day.weekday > DateTime.wednesday) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  final day = anchorDay();
  final morning = day.add(const Duration(hours: 8));
  final evening = day.add(const Duration(hours: 20));
  final tomorrow = day.add(const Duration(days: 1, hours: 8));

  Course course(
    String uid,
    DateTime start, {
    List<String> tags = const [],
    int capacity = 20,
    int subscribed = 5,
  }) =>
      Course(
        id: uid,
        uid: uid,
        name: 'Corso $uid',
        startDate: Timestamp.fromDate(start),
        endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
        capacity: capacity,
        subscribed: subscribed,
        tags: tags,
      );

  final cMorning = course('c-morning', morning);
  final cEvening = course('c-evening', evening);
  final cEveningLate =
      course('c-evening-2', evening.add(const Duration(hours: 1)));
  final cTomorrow = course('c-tomorrow', tomorrow);
  final cHyroxEvening = course('c-hyrox', evening, tags: ['Hyrox']);
  final cFull = course('c-full', evening, capacity: 5, subscribed: 5);

  setUp(() {
    store.dispatch(SetAllCoursesAction([
      cMorning,
      cEvening,
      cEveningLate,
      cTomorrow,
      cHyroxEvening,
      cFull,
    ]));
  });

  CancelledEnrollment lost(
          String courseId, DateTime courseStart, LostKind kind) =>
      CancelledEnrollment(
        courseId: courseId,
        cancelledAt:
            Timestamp.fromDate(courseStart.subtract(const Duration(hours: 1))),
        entryLost: true,
        lostKind: kind,
        courseStartDate: Timestamp.fromDate(courseStart),
      );

  FitropeUser user({
    List<String> courses = const [],
    List<CancelledEnrollment> cancelled = const [],
    TipologiaIscrizione? tipologia,
    int? entrateDisponibili,
    int? entrateSettimanali,
    List<UserSubscription> subscriptions = const [],
    List<String> tags = const ['Open', 'Hyrox'],
  }) =>
      FitropeUser(
        uid: 'u1',
        email: 'u1@example.com',
        name: 'Test',
        lastName: 'User',
        courses: courses,
        tipologiaIscrizione: tipologia,
        entrateDisponibili: entrateDisponibili,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione:
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 60))),
        role: 'User',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
        tipologiaCorsoTags: tags,
        cancelledEnrollments: cancelled,
        activeSubscriptions: subscriptions,
      );

  UserSubscription openFrequency(int weekly) => UserSubscription(
        id: 'sub-open',
        planKey: 'open_${weekly}x_1m',
        family: SubscriptionFamily.OPEN,
        billingMode: BillingMode.FREQUENCY,
        courseTypeTags: const {'Open'},
        weeklyFrequency: weekly,
        startDate: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 10))),
        endDate:
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 60))),
      );

  group('limite settimanale (frequenza)', () {
    test(
        'slot perso nella giornata: il candidato lo assorbe, iscrizione consentita',
        () {
      // 1 corso attivo su 2 a settimana + 1 slot perso nella giornata del
      // candidato: senza netting sarebbe 2/2 → bloccato.
      final u = user(
        courses: ['c-morning'],
        cancelled: [lost('c-tomorrow', morning, LostKind.WEEKLY_SLOT)],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEvening, u), CourseState.CAN_SUBSCRIBE);
    });

    test('slot perso in un altro giorno: nessun assorbimento, limite raggiunto',
        () {
      final u = user(
        courses: ['c-morning'],
        cancelled: [lost('c-tomorrow', tomorrow, LostKind.WEEKLY_SLOT)],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEvening, u), CourseState.LIMIT);
    });

    test('il recupero è uno solo: il secondo corso della giornata è bloccato',
        () {
      final u = user(
        courses: ['c-morning', 'c-evening'],
        cancelled: [lost('c-tomorrow', morning, LostKind.WEEKLY_SLOT)],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEveningLate, u), CourseState.LIMIT);
    });

    test('una perdita di INGRESSO non pesa mai sul limite settimanale', () {
      final u = user(
        courses: ['c-morning'],
        cancelled: [lost('c-tomorrow', tomorrow, LostKind.ENTRY)],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEvening, u), CourseState.CAN_SUBSCRIBE);
    });

    test('senza perdite il conteggio è quello di prima (nessuna regressione)',
        () {
      final atLimit = user(
        courses: ['c-morning', 'c-evening'],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEveningLate, atLimit), CourseState.LIMIT);

      final belowLimit = user(
        courses: ['c-morning'],
        subscriptions: [openFrequency(2)],
      );
      expect(getCourseState(cEvening, belowLimit), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('crediti a ingressi (pacchetto)', () {
    FitropeUser pack({
      List<String> courses = const [],
      List<CancelledEnrollment> cancelled = const [],
      int credits = 0,
    }) =>
        user(
          courses: courses,
          cancelled: cancelled,
          tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: credits,
        );

    test('credito a zero ma ingresso perso nella giornata → consentito', () {
      final u = pack(cancelled: [lost('c-morning', morning, LostKind.ENTRY)]);
      expect(getCourseState(cEvening, u), CourseState.CAN_SUBSCRIBE);
    });

    test('senza la perdita lo stesso utente resta bloccato', () {
      expect(getCourseState(cEvening, pack()), CourseState.SUBSCRIBE_LIMIT);
    });

    test('ingresso perso in un altro giorno → bloccato', () {
      final u = pack(cancelled: [lost('c-tomorrow', tomorrow, LostKind.ENTRY)]);
      expect(getCourseState(cEvening, u), CourseState.SUBSCRIBE_LIMIT);
    });

    test('ingresso perso di un altra tipologia → bloccato', () {
      final u = pack(cancelled: [lost('c-hyrox', evening, LostKind.ENTRY)]);
      expect(getCourseState(cEvening, u), CourseState.SUBSCRIBE_LIMIT);
    });

    test(
        'recupero già assorbito da un altra iscrizione della giornata → bloccato',
        () {
      final u = pack(
        courses: ['c-evening'],
        cancelled: [lost('c-morning', morning, LostKind.ENTRY)],
      );
      expect(getCourseState(cEveningLate, u), CourseState.SUBSCRIBE_LIMIT);
    });

    test('il recupero non supera la capienza', () {
      final u = pack(cancelled: [lost('c-morning', morning, LostKind.ENTRY)]);
      // Corso pieno con waitlist abilitata: resta la lista d'attesa, non l'iscrizione.
      expect(getCourseState(cFull, u), CourseState.CAN_WAITLIST);
    });

    test('uno slot settimanale perso non sblocca un credito a ingressi', () {
      final u =
          pack(cancelled: [lost('c-morning', morning, LostKind.WEEKLY_SLOT)]);
      expect(getCourseState(cEvening, u), CourseState.SUBSCRIBE_LIMIT);
    });
  });

  group('helper di presentazione', () {
    test(
        'recoveryCandidates: stessa giornata e tipologia, con posti, non già iscritto',
        () {
      final u = user(courses: ['c-morning', 'c-evening']);
      final candidates = recoveryCandidates(cMorning, u, now: morning);
      // Esclusi: c-morning (è il corso disdetto), c-evening (già iscritto),
      // c-tomorrow (altro giorno), c-hyrox (altra tipologia), c-full (pieno).
      expect(candidates.map((c) => c.uid), ['c-evening-2']);
    });

    test('recoveryCandidates: nessun corso dopo l ultimo della giornata', () {
      final u = user(courses: ['c-evening-2']);
      expect(recoveryCandidates(cEveningLate, u, now: evening), isEmpty);
    });

    test('pendingRecoveriesToday: perdita non assorbita → recupero pendente',
        () {
      final u = user(cancelled: [lost('c-morning', morning, LostKind.ENTRY)]);
      expect(pendingRecoveriesToday(u, now: morning), {'Open': 1});
    });

    test('pendingRecoveriesToday: perdita assorbita → nessun recupero pendente',
        () {
      final u = user(
        courses: ['c-evening'],
        cancelled: [lost('c-morning', morning, LostKind.ENTRY)],
      );
      expect(pendingRecoveriesToday(u, now: morning), isEmpty);
    });

    test('pendingRecoveriesToday: perdita di ieri non conta oggi', () {
      final u = user(cancelled: [lost('c-morning', morning, LostKind.ENTRY)]);
      expect(pendingRecoveriesToday(u, now: tomorrow), isEmpty);
    });
  });

  group('canUnsubscribe: messaggio di recupero', () {
    test('entro finestra: messaggio e conteggio dei corsi di recupero', () {
      // Corso che inizia tra 2 ore (entro entrambe le finestre 4h/8h).
      final soonStart = DateTime.now().add(const Duration(hours: 2));
      final soon = course('c-soon', soonStart);
      final laterToday = course(
        'c-later',
        DateTime.utc(soonStart.toUtc().year, soonStart.toUtc().month,
                soonStart.toUtc().day)
            .add(const Duration(hours: 23, minutes: 30)),
      );
      store.dispatch(SetAllCoursesAction([soon, laterToday]));

      final u = user(
        courses: ['c-soon'],
        tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 3,
      );
      final info = CourseUnsubscribeHelper.canUnsubscribe(soon, u);

      expect(info['requiresConfirmation'], true);
      expect(info['message'], contains('perdi la lezione'));
      expect(info['message'], contains('un altro corso di oggi'));
      expect(info['courseTypeLabel'], 'Open');
      // laterToday è nella stessa giornata UTC, dopo `soon`, con posti liberi.
      expect(info['recoveryCount'], 1);
    });

    test('fuori finestra: nessun conteggio di recupero da mostrare', () {
      final u = user(
        courses: ['c-tomorrow'],
        tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 3,
      );
      final info = CourseUnsubscribeHelper.canUnsubscribe(cTomorrow, u);
      expect(info['requiresConfirmation'], false);
      expect(info['recoveryCount'], 0);
    });
  });

  group('serializzazione', () {
    test('round-trip di lostKind', () {
      for (final kind in LostKind.values) {
        final json = lost('c-morning', morning, kind).toJson();
        expect(CancelledEnrollment.fromJson(json).lostKind, kind);
      }
    });

    test('record legacy senza lostKind → letto come slot settimanale', () {
      final legacy = <String, dynamic>{
        'courseId': 'c-morning',
        'cancelledAt': Timestamp.fromDate(morning),
        'entryLost': true,
        'courseStartDate': Timestamp.fromDate(morning),
      };
      final parsed = CancelledEnrollment.fromJson(legacy);
      expect(parsed.lostKind, isNull);
      expect(parsed.lostKindOrDefault, LostKind.WEEKLY_SLOT);
    });
  });
}
