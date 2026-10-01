import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = Timestamp.fromMillisecondsSinceEpoch(1780000000000);
  final later = Timestamp.fromMillisecondsSinceEpoch(1780000600000);

  Map<String, dynamic> recordJson({String source = 'self'}) => {
        'courseId': 'c1',
        'userId': 'u1',
        'courseStartMillis': 1780000000000,
        'present': true,
        'source': source,
        'markedBy': 'u1',
        'markedAt': at,
        'updatedAt': later,
      };

  group('AttendanceRecord', () {
    test('docId deterministico courseId_userId', () {
      expect(AttendanceRecord.docId('c1', 'u1'), 'c1_u1');
    });

    test('fromJson/toJson round-trip', () {
      final record = AttendanceRecord.fromJson(recordJson());
      expect(record.courseId, 'c1');
      expect(record.userId, 'u1');
      expect(record.courseStartMillis, 1780000000000);
      expect(record.present, isTrue);
      expect(record.source, AttendanceSource.self);
      expect(record.markedBy, 'u1');
      expect(record.markedAt, at);
      expect(record.updatedAt, later);
      expect(record.toJson(), recordJson());
    });

    test('source sconosciuta o assente → self; isStaffRecorded', () {
      expect(
        AttendanceRecord.fromJson({...recordJson(), 'source': 'boh'}).source,
        AttendanceSource.self,
      );
      expect(AttendanceRecord.fromJson(recordJson()).isStaffRecorded, isFalse);
      expect(
        AttendanceRecord.fromJson(recordJson(source: 'trainer'))
            .isStaffRecorded,
        isTrue,
      );
      expect(
        AttendanceRecord.fromJson(recordJson(source: 'admin')).isStaffRecorded,
        isTrue,
      );
    });

    test('campi mancanti: default sicuri', () {
      final record = AttendanceRecord.fromJson({
        'courseId': 'c1',
        'userId': 'u1',
      });
      expect(record.present, isFalse);
      expect(record.courseStartMillis, 0);
      expect(record.markedAt, isNull);
    });

    test('copyWith', () {
      final record = AttendanceRecord.fromJson(recordJson());
      final copy =
          record.copyWith(present: false, source: AttendanceSource.trainer);
      expect(copy.present, isFalse);
      expect(copy.source, AttendanceSource.trainer);
      expect(copy.courseId, 'c1');
      expect(copy.markedAt, at);
    });
  });

  group('CourseAttendanceSummary e Course.attendance', () {
    Map<String, dynamic> courseJson({Object? attendance}) => {
          'uid': 'c1',
          'name': 'Corso',
          'startDate': at,
          'endDate': later,
          'capacity': 10,
          'subscribed': 2,
          'tags': ['Open'],
          'courseType': 'open',
          'tag': null,
          'courseModelV2': true,
          if (attendance != null) 'attendance': attendance,
        };

    test('fromJson legge il marcatore', () {
      final course = Course.fromJson(courseJson(attendance: {
        'lastMarkedAt': at,
        'lastMarkedBy': 't1',
        'presentCount': 3,
      }));
      expect(course.attendance, isNotNull);
      expect(course.attendance!.presentCount, 3);
      expect(course.attendance!.lastMarkedBy, 't1');
      expect(course.attendance!.lastMarkedAt, at);
    });

    test('marcatore assente → null', () {
      expect(Course.fromJson(courseJson()).attendance, isNull);
    });

    test('toJson NON emette attendance (è server-owned)', () {
      final course = Course.fromJson(courseJson(attendance: {
        'presentCount': 3,
      }));
      expect(course.toJson().containsKey('attendance'), isFalse);
    });

    test('copyWith preserva il marcatore', () {
      final course = Course.fromJson(courseJson(attendance: {
        'presentCount': 3,
      }));
      expect(course.copyWith(name: 'Altro').attendance!.presentCount, 3);
    });
  });
}
