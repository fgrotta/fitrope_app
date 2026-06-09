import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';

/// getCourseState nel modello multi-abbonamento (activeSubscriptions non vuoto):
/// frequenza Open (2x/3x/illimitato), ingressi Hyrox/PT, scoping per famiglia,
/// scadenza per-abbonamento, copertura, e fallback al modello legacy.
void main() {
  final now = DateTime.now();
  // Lunedì della prossima settimana (sempre nel futuro, stessa settimana per i corsi).
  final monday = DateTime(now.year, now.month, now.day)
      .add(Duration(days: 8 - now.weekday));

  Course course({
    required String uid,
    required List<String> tags,
    int dayOffset = 0,
    int capacity = 10,
    int subscribed = 0,
    bool waitlistEnabled = true,
    List<String> waitlist = const [],
  }) {
    final start = monday.add(Duration(days: dayOffset, hours: 10));
    return Course(
      id: uid,
      uid: uid,
      name: uid,
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
      capacity: capacity,
      subscribed: subscribed,
      tags: tags,
      waitlistEnabled: waitlistEnabled,
      waitlist: waitlist,
    );
  }

  UserSubscription sub({
    required SubscriptionFamily family,
    required BillingMode mode,
    required Set<String> tags,
    int? weeklyFrequency,
    int? remainingEntries,
    Duration validFor = const Duration(days: 60),
  }) {
    return UserSubscription(
      planKey: 'test',
      family: family,
      billingMode: mode,
      courseTypeTags: tags,
      weeklyFrequency: weeklyFrequency,
      remainingEntries: remainingEntries,
      startDate: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      endDate: Timestamp.fromDate(now.add(validFor)),
    );
  }

  FitropeUser user({
    List<String> courses = const [],
    List<String> tags = const ['Tutti i corsi'],
    List<UserSubscription> subs = const [],
    List<CancelledEnrollment> cancelled = const [],
  }) {
    return FitropeUser(
      uid: 'u1',
      email: 'e',
      name: 'N',
      lastName: 'C',
      courses: courses,
      role: 'User',
      createdAt: now,
      tipologiaCorsoTags: tags,
      activeSubscriptions: subs,
      cancelledEnrollments: cancelled,
    );
  }

  setUp(() => store.dispatch(SetAllCoursesAction([])));

  group('Open (frequenza)', () {
    test('sotto il limite 2x -> CAN_SUBSCRIBE', () {
      final c1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([c1, target]));
      final u = user(
        courses: ['o1'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('al limite 2x -> LIMIT', () {
      final c1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final c2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([c1, c2, target]));
      final u = user(
        courses: ['o1', 'o2'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.LIMIT);
    });

    test('illimitato (freq null) -> CAN_SUBSCRIBE anche con molti corsi', () {
      final c1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final c2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([c1, c2, target]));
      final u = user(
        courses: ['o1', 'o2'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: null)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('Hyrox / PT (ingressi)', () {
    test('ingressi residui > 0 -> CAN_SUBSCRIBE', () {
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.HYROX],
        subs: [
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: 3)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('ingressi esauriti -> SUBSCRIBE_LIMIT', () {
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.HYROX],
        subs: [
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: 0)
        ],
      );
      expect(getCourseState(target, u), CourseState.SUBSCRIBE_LIMIT);
    });
  });

  group('scoping per famiglia', () {
    test('gli ingressi PT non consumano la frequenza Open', () {
      final pt1 =
          course(uid: 'p1', tags: [CourseTags.PERSONAL_TRAINER], dayOffset: 0);
      final pt2 =
          course(uid: 'p2', tags: [CourseTags.PERSONAL_TRAINER], dayOffset: 1);
      final openTarget =
          course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([pt1, pt2, openTarget]));
      final u = user(
        courses: ['p1', 'p2'],
        tags: [CourseTags.OPEN, CourseTags.PERSONAL_TRAINER],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2),
          sub(
              family: SubscriptionFamily.PT,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.PERSONAL_TRAINER},
              remainingEntries: 5),
        ],
      );
      // I 2 corsi PT NON contano sulla frequenza Open -> Open ancora libera.
      expect(getCourseState(openTarget, u), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('scadenza e copertura', () {
    test('abbonamento scaduto alla data del corso -> EXPIRED', () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2,
              validFor: const Duration(days: -1))
        ],
      );
      expect(getCourseState(target, u), CourseState.EXPIRED);
    });

    test('nessun accesso (no tag, no copertura) -> NULL', () {
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN], // niente accesso tag a Hyrox
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2) // l'abbonamento Open non copre Hyrox
        ],
      );
      expect(getCourseState(target, u), CourseState.NULL);
    });
  });

  group('fallback legacy (activeSubscriptions vuoto)', () {
    test('usa i campi legacy: pacchetto entrate esaurito -> SUBSCRIBE_LIMIT',
        () {
      final target = course(uid: 'o1', tags: const []);
      store.dispatch(SetAllCoursesAction([target]));
      final u = FitropeUser(
        uid: 'u1',
        email: 'e',
        name: 'N',
        lastName: 'C',
        courses: const [],
        role: 'User',
        createdAt: now,
        tipologiaCorsoTags: const ['Tutti i corsi'],
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 0,
      );
      expect(getCourseState(target, u), CourseState.SUBSCRIBE_LIMIT);
    });
  });

  group('accesso e casi limite (gate review)', () {
    test('abbonamento valido sblocca anche con tag legacy non allineati', () {
      // Rottura A del gate: Hyrox valido ma tipologiaCorsoTags=[Open].
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: 5)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('corso tag-only senza abbonamento (Hey Mamma) -> CAN_SUBSCRIBE', () {
      final target = course(uid: 'hm1', tags: [CourseTags.HEY_MAMMA]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.HEY_MAMMA],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('al limite Open ma target Hyrox -> CAN_SUBSCRIBE (scoping reale)', () {
      final o1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final o2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final hTarget = course(uid: 'h1', tags: [CourseTags.HYROX], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([o1, o2, hTarget]));
      final u = user(
        courses: ['o1', 'o2'],
        tags: [CourseTags.OPEN, CourseTags.HYROX],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2),
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: 5),
        ],
      );
      // I 2 corsi Open (al limite) NON contano nello scope Hyrox.
      expect(getCourseState(hTarget, u), CourseState.CAN_SUBSCRIBE);
    });

    test('disiscrizione persa Open conta verso il limite Open', () {
      final active = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final lost = course(uid: 'oc', tags: [CourseTags.OPEN], dayOffset: 1);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([active, lost, target]));
      final u = user(
        courses: ['o1'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
        cancelled: [
          CancelledEnrollment(
            courseId: 'oc',
            cancelledAt: Timestamp.fromDate(now),
            entryLost: true,
            courseStartDate: lost.startDate,
          ),
        ],
      );
      // 1 attivo + 1 perso = limite 2 -> LIMIT.
      expect(getCourseState(target, u), CourseState.LIMIT);
    });

    test('disiscrizione persa PT non conta verso il limite Open', () {
      final active = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final lostPt =
          course(uid: 'pc', tags: [CourseTags.PERSONAL_TRAINER], dayOffset: 1);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([active, lostPt, target]));
      final u = user(
        courses: ['o1'],
        tags: [CourseTags.OPEN, CourseTags.PERSONAL_TRAINER],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
        cancelled: [
          CancelledEnrollment(
            courseId: 'pc',
            cancelledAt: Timestamp.fromDate(now),
            entryLost: true,
            courseStartDate: lostPt.startDate,
          ),
        ],
      );
      // Solo 1 attivo Open conta (il perso PT no) -> CAN_SUBSCRIBE.
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('scadenza al confine: endDate == data corso -> NON scaduto', () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          UserSubscription(
            planKey: 'x',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            courseTypeTags: {CourseTags.OPEN},
            weeklyFrequency: 2,
            startDate:
                Timestamp.fromDate(now.subtract(const Duration(days: 1))),
            endDate: target.startDate, // esattamente la data del corso
          ),
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('ENTRIES con remainingEntries null -> SUBSCRIBE_LIMIT', () {
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.HYROX],
        subs: [
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: null)
        ],
      );
      expect(getCourseState(target, u), CourseState.SUBSCRIBE_LIMIT);
    });

    test('due abbonamenti coprenti (uno scaduto, uno valido) -> CAN_SUBSCRIBE',
        () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2,
              validFor: const Duration(days: -1)),
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2),
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('utente ibrido: activeSubscriptions vince sui campi legacy', () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = FitropeUser(
        uid: 'u1',
        email: 'e',
        name: 'N',
        lastName: 'C',
        courses: const [],
        role: 'User',
        createdAt: now,
        tipologiaCorsoTags: const [CourseTags.OPEN],
        // Legacy esaurito, ma il nuovo modello (Open frequenza) deve prevalere.
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 0,
        activeSubscriptions: [
          UserSubscription(
            planKey: 'x',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            courseTypeTags: {CourseTags.OPEN},
            weeklyFrequency: 2,
            startDate:
                Timestamp.fromDate(now.subtract(const Duration(days: 1))),
            endDate: Timestamp.fromDate(now.add(const Duration(days: 60))),
          ),
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });
  });

  group('capienza, waitlist e confini (gate conferma)', () {
    test('Open al limite + corso pieno + waitlist off -> LIMIT (non FULL)', () {
      final o1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final o2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final target = course(
          uid: 'o3',
          tags: [CourseTags.OPEN],
          dayOffset: 2,
          capacity: 5,
          subscribed: 5,
          waitlistEnabled: false);
      store.dispatch(SetAllCoursesAction([o1, o2, target]));
      final u = user(
        courses: ['o1', 'o2'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.LIMIT);
    });

    test('idoneo + corso pieno + waitlist on -> CAN_WAITLIST', () {
      final target = course(
          uid: 'o1', tags: [CourseTags.OPEN], capacity: 5, subscribed: 5);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.CAN_WAITLIST);
    });

    test(
        'idoneo + posto disponibile + utente in waitlist -> WAITLIST_SPOT_AVAILABLE',
        () {
      final target = course(
          uid: 'o1',
          tags: [CourseTags.OPEN],
          capacity: 10,
          subscribed: 1,
          waitlist: ['u1']);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2)
        ],
      );
      expect(getCourseState(target, u), CourseState.WAITLIST_SPOT_AVAILABLE);
    });

    test('gia iscritto -> SUBSCRIBED anche con abbonamento scaduto', () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        courses: ['o1'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2,
              validFor: const Duration(days: -1))
        ],
      );
      expect(getCourseState(target, u), CourseState.SUBSCRIBED);
    });

    test('frequenza 3x: al limite -> LIMIT, sotto -> CAN_SUBSCRIBE', () {
      final o1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final o2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final o3 = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      final target = course(uid: 'o4', tags: [CourseTags.OPEN], dayOffset: 3);
      store.dispatch(SetAllCoursesAction([o1, o2, o3, target]));
      final atLimit = user(courses: [
        'o1',
        'o2',
        'o3'
      ], tags: [
        CourseTags.OPEN
      ], subs: [
        sub(
            family: SubscriptionFamily.OPEN,
            mode: BillingMode.FREQUENCY,
            tags: {CourseTags.OPEN},
            weeklyFrequency: 3)
      ]);
      expect(getCourseState(target, atLimit), CourseState.LIMIT);
      final under = user(courses: [
        'o1',
        'o2'
      ], tags: [
        CourseTags.OPEN
      ], subs: [
        sub(
            family: SubscriptionFamily.OPEN,
            mode: BillingMode.FREQUENCY,
            tags: {CourseTags.OPEN},
            weeklyFrequency: 3)
      ]);
      expect(getCourseState(target, under), CourseState.CAN_SUBSCRIBE);
    });

    test('ENTRIES al confine: remainingEntries 1 -> CAN_SUBSCRIBE', () {
      final target = course(uid: 'h1', tags: [CourseTags.HYROX]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(tags: [
        CourseTags.HYROX
      ], subs: [
        sub(
            family: SubscriptionFamily.HYROX,
            mode: BillingMode.ENTRIES,
            tags: {CourseTags.HYROX},
            remainingEntries: 1)
      ]);
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test('abbonamento con startDate futuro -> non valido (EXPIRED)', () {
      final target = course(uid: 'o1', tags: [CourseTags.OPEN]);
      store.dispatch(SetAllCoursesAction([target]));
      final u = user(
        tags: [CourseTags.OPEN],
        subs: [
          UserSubscription(
            planKey: 'x',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            courseTypeTags: {CourseTags.OPEN},
            weeklyFrequency: 2,
            startDate: Timestamp.fromDate(now.add(const Duration(days: 30))),
            endDate: Timestamp.fromDate(now.add(const Duration(days: 60))),
          ),
        ],
      );
      expect(getCourseState(target, u), CourseState.EXPIRED);
    });

    test('due abbonamenti stessa famiglia (2x + 3x): vince il piu generoso',
        () {
      final o1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final o2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final target = course(uid: 'o3', tags: [CourseTags.OPEN], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([o1, o2, target]));
      final u = user(
        courses: ['o1', 'o2'],
        tags: [CourseTags.OPEN],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2),
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 3),
        ],
      );
      // Il 2x è al limite ma il 3x consente (2 < 3).
      expect(getCourseState(target, u), CourseState.CAN_SUBSCRIBE);
    });

    test(
        'corso multi-tag [Open,Hyrox]: tipologia primaria Open, no bypass via Hyrox',
        () {
      final o1 = course(uid: 'o1', tags: [CourseTags.OPEN], dayOffset: 0);
      final o2 = course(uid: 'o2', tags: [CourseTags.OPEN], dayOffset: 1);
      final multi = course(
          uid: 'm1', tags: [CourseTags.OPEN, CourseTags.HYROX], dayOffset: 2);
      store.dispatch(SetAllCoursesAction([o1, o2, multi]));
      final u = user(
        courses: ['o1', 'o2'], // Open al limite 2x
        tags: [CourseTags.OPEN, CourseTags.HYROX],
        subs: [
          sub(
              family: SubscriptionFamily.OPEN,
              mode: BillingMode.FREQUENCY,
              tags: {CourseTags.OPEN},
              weeklyFrequency: 2),
          sub(
              family: SubscriptionFamily.HYROX,
              mode: BillingMode.ENTRIES,
              tags: {CourseTags.HYROX},
              remainingEntries: 5),
        ],
      );
      // Tipologia primaria = Open (primo tag): si valuta solo l'Open, al limite -> LIMIT.
      expect(getCourseState(multi, u), CourseState.LIMIT);
    });
  });
}
