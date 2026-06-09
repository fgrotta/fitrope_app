import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/getCourseState.dart';

void main() {
  group('FitropeUser defaults and legacy parsing', () {
    test('constructor default tags stay aligned with CourseTags.defaultUserTags', () {
      final user = FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: const [],
        role: 'User',
        createdAt: DateTime.now(),
      );

      expect(user.tipologiaCorsoTags, CourseTags.defaultUserTags);
    });

    test('fromJson defaults tipologiaCorsoTags to OPEN for legacy users', () {
      final user = FitropeUser.fromJson({
        'uid': 'legacy-user',
        'email': 'legacy@example.com',
        'name': 'Legacy',
        'lastName': 'User',
        'courses': const <String>[],
        'role': 'User',
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });

      expect(user.tipologiaCorsoTags, CourseTags.defaultUserTags);
    });

    test('fromJson keeps unknown tipologiaIscrizione as null instead of throwing', () {
      final user = FitropeUser.fromJson({
        'uid': 'legacy-user',
        'email': 'legacy@example.com',
        'name': 'Legacy',
        'lastName': 'User',
        'courses': const <String>[],
        'role': 'User',
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'tipologiaIscrizione': 'TIPO_NON_VALIDO',
      });

      expect(user.tipologiaIscrizione, isNull);
    });
  });

  group('Course.fromJson legacy ids', () {
    test('falls back to deprecated id when uid is missing', () {
      final course = Course.fromJson({
        'id': 'legacy-course',
        'name': 'Corso Legacy',
        'startDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1, hours: 1))),
        'capacity': 10,
        'subscribed': 0,
      });

      expect(course.uid, 'legacy-course');
      expect(course.id, 'legacy-course');
    });

    test('prefers uid over deprecated id when both are present', () {
      final course = Course.fromJson({
        'uid': 'new-course',
        'id': 'legacy-course',
        'name': 'Corso',
        'startDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1, hours: 1))),
        'capacity': 10,
        'subscribed': 0,
      });

      expect(course.uid, 'new-course');
      expect(course.id, 'new-course');
    });
  });

  group('getCourseState uncovered branches', () {
    late DateTime mondayNextWeek;

    setUp(() {
      store.dispatch(SetAllCoursesAction([]));
      final now = DateTime.now();
      mondayNextWeek =
          now.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7));
    });

    Course makeCourse({
      required String uid,
      required DateTime startDate,
      int capacity = 10,
      int subscribed = 0,
      List<String> waitlist = const [],
    }) {
      return Course(
        id: uid,
        uid: uid,
        name: 'Corso $uid',
        startDate: Timestamp.fromDate(startDate),
        endDate: Timestamp.fromDate(startDate.add(const Duration(hours: 1))),
        capacity: capacity,
        subscribed: subscribed,
        waitlist: waitlist,
      );
    }

    FitropeUser makeTemporalUser({
      required List<String> courses,
      int? entrateSettimanali,
    }) {
      return FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: courses,
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 30))),
        role: 'User',
        createdAt: DateTime.now(),
      );
    }

    test('user in waitlist with free spot still sees LIMIT when weekly quota is exhausted', () {
      final bookedCourse = makeCourse(
        uid: 'booked-course',
        startDate: mondayNextWeek.add(const Duration(hours: 10)),
      );
      final waitlistCourse = makeCourse(
        uid: 'waitlist-course',
        startDate: mondayNextWeek.add(const Duration(days: 1, hours: 10)),
        subscribed: 9,
        capacity: 10,
        waitlist: const ['user-1'],
      );

      store.dispatch(SetAllCoursesAction([bookedCourse, waitlistCourse]));

      final user = makeTemporalUser(
        courses: const ['booked-course'],
        entrateSettimanali: 1,
      );

      expect(getCourseState(waitlistCourse, user), CourseState.LIMIT);
    });

    test('weekly count ignores stale course ids that are missing from the store', () {
      final targetCourse = makeCourse(
        uid: 'target-course',
        startDate: mondayNextWeek.add(const Duration(days: 2, hours: 10)),
        subscribed: 5,
        capacity: 10,
      );

      store.dispatch(SetAllCoursesAction([targetCourse]));

      final user = makeTemporalUser(
        courses: const ['ghost-course'],
        entrateSettimanali: 1,
      );

      expect(getCourseState(targetCourse, user), CourseState.CAN_SUBSCRIBE);
    });
  });
}
