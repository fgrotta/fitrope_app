import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/get_course_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matrice di regressione del read-path client.
///
/// I casi qui usano una settimana futura deterministica rispetto al run: non
/// dipendono né dal giorno corrente né dalla pulizia periodica dello snapshot.
void main() {
  final now = DateTime.now();
  final nextMonday = DateTime(now.year, now.month, now.day)
      .add(Duration(days: 8 - now.weekday));

  Course course(
    String id, {
    String tag = CourseTags.OPEN,
    DateTime? start,
    int capacity = 10,
    int subscribed = 0,
  }) {
    final courseStart = start ?? nextMonday.add(const Duration(hours: 10));
    return Course(
      id: id,
      uid: id,
      name: id,
      startDate: Timestamp.fromDate(courseStart),
      endDate: Timestamp.fromDate(courseStart.add(const Duration(hours: 1))),
      capacity: capacity,
      subscribed: subscribed,
      tags: [tag],
    );
  }

  FitropeUser user({
    List<String> courses = const [],
    List<String> tags = const [CourseTags.OPEN],
    List<UserSubscription> subscriptions = const [],
    List<CancelledEnrollment> cancelled = const [],
    TipologiaIscrizione? legacyType,
    int? availableEntries,
    int? weeklyEntries,
    Timestamp? legacyEnd,
  }) =>
      FitropeUser(
        uid: 'matrix-user',
        email: 'matrix@test.it',
        name: 'Matrix',
        lastName: 'Test',
        role: 'User',
        courses: courses,
        createdAt: now,
        tipologiaCorsoTags: tags,
        activeSubscriptions: subscriptions,
        cancelledEnrollments: cancelled,
        tipologiaIscrizione: legacyType,
        entrateDisponibili: availableEntries,
        entrateSettimanali: weeklyEntries,
        fineIscrizione: legacyEnd,
      );

  UserSubscription subscription({
    required SubscriptionFamily family,
    required BillingMode billingMode,
    required Set<String> tags,
    int? weeklyFrequency,
    int? remainingEntries,
    DateTime? start,
    DateTime? end,
  }) =>
      UserSubscription(
        planKey: 'matrix',
        family: family,
        billingMode: billingMode,
        courseTypeTags: tags,
        weeklyFrequency: weeklyFrequency,
        remainingEntries: remainingEntries,
        startDate:
            Timestamp.fromDate(start ?? now.subtract(const Duration(days: 1))),
        endDate: Timestamp.fromDate(end ?? now.add(const Duration(days: 60))),
      );

  setUp(() => store.dispatch(SetAllCoursesAction([])));

  group('Open FREQUENCY', () {
    for (final frequency in [2, 3]) {
      test('${frequency}x: sotto quota e al limite', () {
        final used = List.generate(
          frequency,
          (index) => course(
            'open-$frequency-$index',
            start: nextMonday.add(Duration(days: index, hours: 10)),
          ),
        );
        final target = course(
          'open-$frequency-target',
          start: nextMonday.add(Duration(days: frequency, hours: 10)),
        );
        store.dispatch(SetAllCoursesAction([...used, target]));

        final sub = subscription(
          family: SubscriptionFamily.OPEN,
          billingMode: BillingMode.FREQUENCY,
          tags: {CourseTags.OPEN},
          weeklyFrequency: frequency,
        );
        expect(
          getCourseState(
              target,
              user(
                  courses: used.take(frequency - 1).map((c) => c.uid).toList(),
                  subscriptions: [sub])),
          CourseState.CAN_SUBSCRIBE,
        );
        expect(
          getCourseState(
              target,
              user(
                  courses: used.map((c) => c.uid).toList(),
                  subscriptions: [sub])),
          CourseState.LIMIT,
        );
      });
    }

    test('illimitato resta idoneo anche con molti corsi nella settimana', () {
      final used = List.generate(
        6,
        (index) => course(
          'open-unlimited-$index',
          start: nextMonday.add(Duration(days: index, hours: 10)),
        ),
      );
      final target = course(
        'open-unlimited-target',
        start: nextMonday.add(const Duration(days: 6, hours: 10)),
      );
      store.dispatch(SetAllCoursesAction([...used, target]));

      expect(
        getCourseState(
          target,
          user(
            courses: used.map((c) => c.uid).toList(),
            subscriptions: [
              subscription(
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.FREQUENCY,
                tags: {CourseTags.OPEN},
              ),
            ],
          ),
        ),
        CourseState.CAN_SUBSCRIBE,
      );
    });

    test('il conteggio si azzera nella settimana successiva', () {
      final previous = course(
        'open-previous-week',
        start: nextMonday
            .subtract(const Duration(days: 7))
            .add(const Duration(hours: 10)),
      );
      final target = course('open-new-week');
      store.dispatch(SetAllCoursesAction([previous, target]));

      expect(
        getCourseState(
          target,
          user(
            courses: [previous.uid],
            subscriptions: [
              subscription(
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.FREQUENCY,
                tags: {CourseTags.OPEN},
                weeklyFrequency: 1,
              ),
            ],
          ),
        ),
        CourseState.CAN_SUBSCRIBE,
      );
    });

    test('Hyrox/PT non consumano la quota Open e le perdite Open sì', () {
      final hyrox = course(
        'hyrox-same-week',
        tag: CourseTags.HYROX,
        start: nextMonday.add(const Duration(hours: 10)),
      );
      final pt = course(
        'pt-same-week',
        tag: CourseTags.PERSONAL_TRAINER,
        start: nextMonday.add(const Duration(days: 1, hours: 10)),
      );
      final lostOpen = course(
        'open-lost',
        start: nextMonday.add(const Duration(days: 2, hours: 10)),
      );
      final target = course(
        'open-target',
        start: nextMonday.add(const Duration(days: 3, hours: 10)),
      );
      store.dispatch(SetAllCoursesAction([hyrox, pt, lostOpen, target]));
      final sub = subscription(
        family: SubscriptionFamily.OPEN,
        billingMode: BillingMode.FREQUENCY,
        tags: {CourseTags.OPEN},
        weeklyFrequency: 1,
      );

      expect(
        getCourseState(
          target,
          user(
            courses: [hyrox.uid, pt.uid],
            tags: const [
              CourseTags.OPEN,
              CourseTags.HYROX,
              CourseTags.PERSONAL_TRAINER
            ],
            subscriptions: [sub],
          ),
        ),
        CourseState.CAN_SUBSCRIBE,
      );
      expect(
        getCourseState(
          target,
          user(
            cancelled: [
              CancelledEnrollment(
                courseId: lostOpen.uid,
                cancelledAt: Timestamp.fromDate(now),
                courseStartDate: lostOpen.startDate,
                entryLost: true,
              ),
            ],
            subscriptions: [sub],
          ),
        ),
        CourseState.LIMIT,
      );
    });
  });

  group('nuovo modello ENTRIES', () {
    for (final row in [
      (label: 'Hyrox', tag: CourseTags.HYROX, family: SubscriptionFamily.HYROX),
      (
        label: 'PT',
        tag: CourseTags.PERSONAL_TRAINER,
        family: SubscriptionFamily.PT
      ),
    ]) {
      test('${row.label}: 1 ingresso, 0 ingressi e scaduto', () {
        final target = course('entries-${row.label}', tag: row.tag);
        store.dispatch(SetAllCoursesAction([target]));

        FitropeUser withEntries(int entries, {DateTime? end}) => user(
              tags: [row.tag],
              subscriptions: [
                subscription(
                  family: row.family,
                  billingMode: BillingMode.ENTRIES,
                  tags: {row.tag},
                  remainingEntries: entries,
                  end: end,
                ),
              ],
            );

        expect(
            getCourseState(target, withEntries(1)), CourseState.CAN_SUBSCRIBE);
        expect(getCourseState(target, withEntries(0)),
            CourseState.SUBSCRIBE_LIMIT);
        expect(
          getCourseState(
              target,
              withEntries(1,
                  end: nextMonday.subtract(const Duration(seconds: 1)))),
          CourseState.EXPIRED,
        );
      });
    }
  });

  group('legacy', () {
    for (final type in [
      TipologiaIscrizione.PACCHETTO_ENTRATE,
      TipologiaIscrizione.ABBONAMENTO_PROVA,
    ]) {
      test('${type.name}: 1 ingresso, 0 ingressi e scaduto', () {
        final target = course('legacy-${type.name}');
        store.dispatch(SetAllCoursesAction([target]));
        final liveEnd =
            Timestamp.fromDate(nextMonday.add(const Duration(days: 30)));

        expect(
          getCourseState(target,
              user(legacyType: type, availableEntries: 1, legacyEnd: liveEnd)),
          CourseState.CAN_SUBSCRIBE,
        );
        expect(
          getCourseState(target,
              user(legacyType: type, availableEntries: 0, legacyEnd: liveEnd)),
          CourseState.SUBSCRIBE_LIMIT,
        );
        expect(
          getCourseState(
            target,
            user(
              legacyType: type,
              availableEntries: 1,
              legacyEnd: Timestamp.fromDate(
                  nextMonday.subtract(const Duration(seconds: 1))),
            ),
          ),
          CourseState.EXPIRED,
        );
      });
    }

    for (final type in [
      TipologiaIscrizione.ABBONAMENTO_MENSILE,
      TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
      TipologiaIscrizione.ABBONAMENTO_SEMESTRALE,
      TipologiaIscrizione.ABBONAMENTO_ANNUALE,
    ]) {
      test('${type.name}: quota, limite e scadenza', () {
        final used = course(
          'legacy-used-${type.name}',
          start: nextMonday.add(const Duration(hours: 10)),
        );
        final target = course(
          'legacy-target-${type.name}',
          start: nextMonday.add(const Duration(days: 1, hours: 10)),
        );
        store.dispatch(SetAllCoursesAction([used, target]));
        final liveEnd =
            Timestamp.fromDate(nextMonday.add(const Duration(days: 30)));

        expect(
          getCourseState(
            target,
            user(
              courses: [used.uid],
              legacyType: type,
              weeklyEntries: 2,
              legacyEnd: liveEnd,
            ),
          ),
          CourseState.CAN_SUBSCRIBE,
        );
        expect(
          getCourseState(
            target,
            user(
              courses: [used.uid],
              legacyType: type,
              weeklyEntries: 1,
              legacyEnd: liveEnd,
            ),
          ),
          CourseState.LIMIT,
        );
        expect(
          getCourseState(
            target,
            user(
              legacyType: type,
              weeklyEntries: 2,
              legacyEnd: Timestamp.fromDate(
                  nextMonday.subtract(const Duration(seconds: 1))),
            ),
          ),
          CourseState.EXPIRED,
        );
      });
    }
  });

  test('un corso pieno conserva il rifiuto di limite invece della waitlist',
      () {
    final target = course('full-exhausted', capacity: 1, subscribed: 1);
    store.dispatch(SetAllCoursesAction([target]));
    expect(
      getCourseState(
        target,
        user(
          legacyType: TipologiaIscrizione.PACCHETTO_ENTRATE,
          availableEntries: 0,
          legacyEnd:
              Timestamp.fromDate(nextMonday.add(const Duration(days: 30))),
        ),
      ),
      CourseState.SUBSCRIBE_LIMIT,
    );
  });
}
