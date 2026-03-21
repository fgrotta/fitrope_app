import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

void main() {
  group('Course', () {
    final startDate = Timestamp.fromDate(DateTime(2024, 6, 1, 10, 0));
    final endDate = Timestamp.fromDate(DateTime(2024, 6, 1, 11, 0));

    Map<String, dynamic> baseJson() => {
          'uid': 'course-123',
          'name': 'Yoga',
          'startDate': startDate,
          'endDate': endDate,
          'capacity': 15,
          'subscribed': 3,
          'trainerId': 'trainer-1',
          'tags': ['Open'],
          'waitlist': ['user-a'],
        };

    group('fromJson', () {
      test('parses all fields correctly', () {
        final course = Course.fromJson(baseJson());
        expect(course.uid, 'course-123');
        expect(course.name, 'Yoga');
        expect(course.capacity, 15);
        expect(course.subscribed, 3);
        expect(course.trainerId, 'trainer-1');
        expect(course.tags, ['Open']);
        expect(course.waitlist, ['user-a']);
      });

      test('falls back to "id" field when "uid" is absent', () {
        final json = baseJson()..remove('uid');
        json['id'] = 'from-id-field';
        final course = Course.fromJson(json);
        expect(course.uid, 'from-id-field');
      });

      test('defaults tags to empty list when absent', () {
        final json = baseJson()..remove('tags');
        final course = Course.fromJson(json);
        expect(course.tags, []);
      });

      test('defaults waitlist to empty list when absent', () {
        final json = baseJson()..remove('waitlist');
        final course = Course.fromJson(json);
        expect(course.waitlist, []);
      });

      test('trainerId can be null', () {
        final json = baseJson();
        json['trainerId'] = null;
        final course = Course.fromJson(json);
        expect(course.trainerId, isNull);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final course = Course(
          id: 'course-123',
          uid: 'course-123',
          name: 'Yoga',
          startDate: startDate,
          endDate: endDate,
          capacity: 15,
          subscribed: 3,
          trainerId: 'trainer-1',
          tags: ['Open'],
          waitlist: ['user-a'],
        );
        final json = course.toJson();

        expect(json['uid'], 'course-123');
        expect(json['name'], 'Yoga');
        expect(json['capacity'], 15);
        expect(json['subscribed'], 3);
        expect(json['trainerId'], 'trainer-1');
        expect(json['tags'], ['Open']);
        expect(json['waitlist'], ['user-a']);
      });

      test('roundtrip fromJson -> toJson preserves uid', () {
        final course = Course.fromJson(baseJson());
        expect(course.toJson()['uid'], course.uid);
      });
    });
  });

  group('FitropeUser', () {
    final createdAt = Timestamp.fromDate(DateTime(2023, 1, 15));
    final fineIscrizione = Timestamp.fromDate(DateTime(2025, 1, 15));
    final certificato = Timestamp.fromDate(DateTime(2025, 6, 1));

    Map<String, dynamic> baseJson() => {
          'uid': 'user-abc',
          'email': 'mario@test.com',
          'name': 'Mario',
          'lastName': 'Rossi',
          'courses': ['course-1', 'course-2'],
          'tipologiaIscrizione': 'ABBONAMENTO_MENSILE',
          'entrateDisponibili': null,
          'entrateSettimanali': 3,
          'fineIscrizione': fineIscrizione,
          'role': 'User',
          'isActive': true,
          'isAnonymous': false,
          'createdAt': createdAt,
          'certificatoScadenza': certificato,
          'numeroTelefono': '3331234567',
          'tipologiaCorsoTags': ['Open'],
          'cancelledEnrollments': [],
          'waitlistCourses': ['course-3'],
        };

    group('fromJson', () {
      test('parses all fields correctly', () {
        final user = FitropeUser.fromJson(baseJson());
        expect(user.uid, 'user-abc');
        expect(user.email, 'mario@test.com');
        expect(user.name, 'Mario');
        expect(user.lastName, 'Rossi');
        expect(user.courses, ['course-1', 'course-2']);
        expect(user.tipologiaIscrizione, TipologiaIscrizione.ABBONAMENTO_MENSILE);
        expect(user.entrateSettimanali, 3);
        expect(user.role, 'User');
        expect(user.isActive, true);
        expect(user.isAnonymous, false);
        expect(user.numeroTelefono, '3331234567');
        expect(user.tipologiaCorsoTags, ['Open']);
        expect(user.waitlistCourses, ['course-3']);
      });

      test('defaults role to "User" when absent', () {
        final json = baseJson()..remove('role');
        final user = FitropeUser.fromJson(json);
        expect(user.role, 'User');
      });

      test('defaults isActive to true when absent', () {
        final json = baseJson()..remove('isActive');
        final user = FitropeUser.fromJson(json);
        expect(user.isActive, true);
      });

      test('defaults courses to empty list when absent', () {
        final json = baseJson()..remove('courses');
        final user = FitropeUser.fromJson(json);
        expect(user.courses, []);
      });

      test('defaults waitlistCourses to empty list when absent', () {
        final json = baseJson()..remove('waitlistCourses');
        final user = FitropeUser.fromJson(json);
        expect(user.waitlistCourses, []);
      });

      test('defaults cancelledEnrollments to empty list when absent', () {
        final json = baseJson()..remove('cancelledEnrollments');
        final user = FitropeUser.fromJson(json);
        expect(user.cancelledEnrollments, []);
      });

      test('null tipologiaIscrizione is allowed', () {
        final json = baseJson();
        json['tipologiaIscrizione'] = null;
        final user = FitropeUser.fromJson(json);
        expect(user.tipologiaIscrizione, isNull);
      });

      test('unknown tipologiaIscrizione string returns null', () {
        final json = baseJson();
        json['tipologiaIscrizione'] = 'UNKNOWN_TYPE';
        final user = FitropeUser.fromJson(json);
        expect(user.tipologiaIscrizione, isNull);
      });

      test('email defaults to empty string when absent', () {
        final json = baseJson()..remove('email');
        final user = FitropeUser.fromJson(json);
        expect(user.email, '');
      });
    });

    group('toJson', () {
      test('serializes tipologiaIscrizione as string', () {
        final user = FitropeUser.fromJson(baseJson());
        final json = user.toJson();
        expect(json['tipologiaIscrizione'], 'ABBONAMENTO_MENSILE');
      });

      test('serializes courses list', () {
        final user = FitropeUser.fromJson(baseJson());
        final json = user.toJson();
        expect(json['courses'], ['course-1', 'course-2']);
      });

      test('roundtrip uid is preserved', () {
        final user = FitropeUser.fromJson(baseJson());
        expect(user.toJson()['uid'], user.uid);
      });
    });

    group('CancelledEnrollment', () {
      test('fromJson parses correctly', () {
        final ts = Timestamp.fromDate(DateTime(2024, 5, 1));
        final json = {
          'courseId': 'c1',
          'cancelledAt': ts,
          'entryLost': true,
          'courseStartDate': ts,
        };
        final e = CancelledEnrollment.fromJson(json);
        expect(e.courseId, 'c1');
        expect(e.entryLost, true);
      });

      test('toJson roundtrip preserves entryLost', () {
        final ts = Timestamp.fromDate(DateTime(2024, 5, 1));
        final e = CancelledEnrollment(
          courseId: 'c1',
          cancelledAt: ts,
          entryLost: false,
          courseStartDate: ts,
        );
        expect(e.toJson()['entryLost'], false);
      });
    });
  });

  group('TipologiaIscrizione enum', () {
    test('all expected values exist', () {
      expect(TipologiaIscrizione.values.length, 6);
      expect(TipologiaIscrizione.values, containsAll([
        TipologiaIscrizione.PACCHETTO_ENTRATE,
        TipologiaIscrizione.ABBONAMENTO_MENSILE,
        TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_SEMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_ANNUALE,
        TipologiaIscrizione.ABBONAMENTO_PROVA,
      ]));
    });
  });
}
