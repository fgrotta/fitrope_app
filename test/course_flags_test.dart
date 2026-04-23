import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/services/email_templates.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Course reminderEnabled / waitlistEnabled', () {
    late DateTime futureDate;

    setUp(() {
      store.dispatch(SetAllCoursesAction([]));
      futureDate = DateTime.now().add(const Duration(days: 3));
    });

    Course makeCourse({
      required int capacity,
      required int subscribed,
      bool reminderEnabled = true,
      bool waitlistEnabled = true,
      List<String> waitlist = const [],
    }) {
      return Course(
        id: 'c1',
        uid: 'c1',
        name: 'Corso Test',
        startDate: Timestamp.fromDate(futureDate),
        endDate: Timestamp.fromDate(futureDate.add(const Duration(hours: 1))),
        capacity: capacity,
        subscribed: subscribed,
        waitlist: waitlist,
        reminderEnabled: reminderEnabled,
        waitlistEnabled: waitlistEnabled,
      );
    }

    FitropeUser makeEligibleUser({String uid = 'user-1'}) {
      return FitropeUser(
        uid: uid,
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        role: 'User',
        createdAt: DateTime.now(),
      );
    }

    group('Default values', () {
      test('reminderEnabled true di default', () {
        final c = Course(
          id: 'c',
          uid: 'c',
          name: 'N',
          startDate: Timestamp.fromDate(DateTime.now()),
          endDate: Timestamp.fromDate(DateTime.now()),
          capacity: 10,
          subscribed: 0,
        );
        expect(c.reminderEnabled, true);
      });

      test('waitlistEnabled true di default', () {
        final c = Course(
          id: 'c',
          uid: 'c',
          name: 'N',
          startDate: Timestamp.fromDate(DateTime.now()),
          endDate: Timestamp.fromDate(DateTime.now()),
          capacity: 10,
          subscribed: 0,
        );
        expect(c.waitlistEnabled, true);
      });
    });

    group('Serializzazione', () {
      test('toJson include i nuovi flag', () {
        final c = makeCourse(capacity: 10, subscribed: 0, reminderEnabled: false, waitlistEnabled: false);
        final json = c.toJson();
        expect(json['reminderEnabled'], false);
        expect(json['waitlistEnabled'], false);
      });

      test('fromJson legge i nuovi flag', () {
        final c = makeCourse(capacity: 10, subscribed: 0);
        final json = c.toJson();
        json['reminderEnabled'] = false;
        json['waitlistEnabled'] = false;
        final restored = Course.fromJson(json);
        expect(restored.reminderEnabled, false);
        expect(restored.waitlistEnabled, false);
      });

      test('fromJson fallback a true per corsi legacy senza flag', () {
        final legacy = {
          'uid': 'c',
          'name': 'N',
          'startDate': Timestamp.fromDate(DateTime.now()),
          'endDate': Timestamp.fromDate(DateTime.now()),
          'capacity': 10,
          'subscribed': 0,
        };
        final restored = Course.fromJson(legacy);
        expect(restored.reminderEnabled, true);
        expect(restored.waitlistEnabled, true);
      });
    });

    group('getCourseState con waitlistEnabled', () {
      test('corso pieno + waitlistEnabled true → CAN_WAITLIST', () {
        final c = makeCourse(capacity: 10, subscribed: 10, waitlistEnabled: true);
        store.dispatch(SetAllCoursesAction([c]));
        expect(getCourseState(c, makeEligibleUser()), CourseState.CAN_WAITLIST);
      });

      test('corso pieno + waitlistEnabled false → FULL', () {
        final c = makeCourse(capacity: 10, subscribed: 10, waitlistEnabled: false);
        store.dispatch(SetAllCoursesAction([c]));
        expect(getCourseState(c, makeEligibleUser()), CourseState.FULL);
      });

      test('corso pieno + waitlistEnabled false + utente già in waitlist → FULL', () {
        // L'utente potrebbe essere rimasto in waitlist da quando il flag era true.
        // Con waitlistEnabled false, non proponiamo più lo stato IN_WAITLIST.
        final c = makeCourse(
          capacity: 10,
          subscribed: 10,
          waitlistEnabled: false,
          waitlist: ['user-1'],
        );
        store.dispatch(SetAllCoursesAction([c]));
        expect(getCourseState(c, makeEligibleUser()), CourseState.FULL);
      });

      test('corso con posti + utente in waitlist + waitlistEnabled true → WAITLIST_SPOT_AVAILABLE', () {
        final c = makeCourse(
          capacity: 10,
          subscribed: 5,
          waitlistEnabled: true,
          waitlist: ['user-1'],
        );
        store.dispatch(SetAllCoursesAction([c]));
        expect(getCourseState(c, makeEligibleUser()), CourseState.WAITLIST_SPOT_AVAILABLE);
      });

      test('corso con posti + utente in waitlist + waitlistEnabled false → CAN_SUBSCRIBE', () {
        final c = makeCourse(
          capacity: 10,
          subscribed: 5,
          waitlistEnabled: false,
          waitlist: ['user-1'],
        );
        store.dispatch(SetAllCoursesAction([c]));
        expect(getCourseState(c, makeEligibleUser()), CourseState.CAN_SUBSCRIBE);
      });
    });
  });

  group('Email templates con logo', () {
    test('trialReminderBody contiene il tag img con src https', () {
      final body = trialReminderBody(
        courseName: 'Pilates',
        courseDate: 'Lunedì 1 Gennaio 2027',
        courseTime: '10:00 - 11:00',
      );
      expect(body, contains('<img'));
      expect(body, contains('src="https://'));
      expect(body, contains('alt="Fit House"'));
    });

    test('waitlistSpotAvailableBody contiene il tag img con src https', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Pilates',
        courseDate: 'Lunedì 1 Gennaio 2027',
        courseTime: '10:00 - 11:00',
        spotsAvailable: 1,
      );
      expect(body, contains('<img'));
      expect(body, contains('src="https://'));
      expect(body, contains('alt="Fit House"'));
    });
  });
}
