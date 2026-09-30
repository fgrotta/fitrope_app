import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/attendance_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Mar 9 giu 2026, 18:00 ora di Roma (16:00 UTC).
  final start = DateTime.utc(2026, 6, 9, 16);
  final course = Course(
    id: 'c1',
    uid: 'c1',
    name: 'Corso',
    startDate: Timestamp.fromDate(start),
    endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
    capacity: 10,
    subscribed: 2,
  );
  DateTime at(int minutes, {int ms = 0}) =>
      start.add(Duration(minutes: minutes, milliseconds: ms));

  AttendanceRecord record(bool present, AttendanceSource source) =>
      AttendanceRecord(
        courseId: 'c1',
        userId: 'u1',
        courseStartMillis: start.millisecondsSinceEpoch,
        present: present,
        source: source,
      );

  group('selfCheckInState', () {
    test('non iscritto → null, a prescindere da tempo e record', () {
      expect(
        selfCheckInState(course, null, at(0), isSubscribed: false),
        isNull,
      );
      expect(
        selfCheckInState(
          course,
          record(true, AttendanceSource.self),
          at(0),
          isSubscribed: false,
        ),
        isNull,
      );
    });

    test('confini della finestra [-15\', +30\'] inclusivi', () {
      SelfCheckInState? s(DateTime now) =>
          selfCheckInState(course, null, now, isSubscribed: true);
      expect(s(at(-15, ms: -1)), SelfCheckInState.notYetOpen);
      expect(s(at(-15)), SelfCheckInState.open);
      expect(s(at(0)), SelfCheckInState.open);
      expect(s(at(30)), SelfCheckInState.open);
      expect(s(at(30, ms: 1)), SelfCheckInState.closedAskTrainer);
    });

    test('il record vince sul tempo', () {
      for (final now in [at(-60), at(0), at(120)]) {
        expect(
          selfCheckInState(
            course,
            record(true, AttendanceSource.self),
            now,
            isSubscribed: true,
          ),
          SelfCheckInState.presentSelf,
        );
        expect(
          selfCheckInState(
            course,
            record(true, AttendanceSource.trainer),
            now,
            isSubscribed: true,
          ),
          SelfCheckInState.presentStaff,
        );
        expect(
          selfCheckInState(
            course,
            record(false, AttendanceSource.admin),
            now,
            isSubscribed: true,
          ),
          SelfCheckInState.absentStaff,
        );
      }
    });

    test('l\'avviso "chiedi al trainer" vale solo nel giorno del corso', () {
      // 23:59 di Roma dello stesso giorno: ancora avviso.
      final lateSameDay = DateTime.utc(2026, 6, 9, 21, 59);
      expect(
        selfCheckInState(course, null, lateSameDay, isSubscribed: true),
        SelfCheckInState.closedAskTrainer,
      );
      // 00:00 di Roma del giorno dopo: niente più avviso.
      final nextDay = DateTime.utc(2026, 6, 9, 22);
      expect(
        selfCheckInState(course, null, nextDay, isSubscribed: true),
        isNull,
      );
    });
  });

  group('staffCanMark', () {
    test('da -30\' in poi, senza limite superiore', () {
      expect(staffCanMark(course, at(-30, ms: -1)), isFalse);
      expect(staffCanMark(course, at(-30)), isTrue);
      expect(staffCanMark(course, at(60 * 24 * 7)), isTrue);
    });
  });

  group('nextAttendanceBoundary', () {
    test('restituisce il prossimo confine dopo now', () {
      int? next(DateTime now) =>
          nextAttendanceBoundary(course, now)?.millisecondsSinceEpoch;
      expect(next(at(-120)), at(-30).millisecondsSinceEpoch);
      expect(next(at(-30)), at(-15).millisecondsSinceEpoch);
      expect(next(at(-15)), at(30, ms: 1).millisecondsSinceEpoch);
      expect(
        next(at(30, ms: 1)),
        DateTime.utc(2026, 6, 9, 22).millisecondsSinceEpoch,
      );
      expect(next(DateTime.utc(2026, 6, 9, 22)), isNull);
    });
  });

  test('isMarkedPresent', () {
    expect(isMarkedPresent(null), isFalse);
    expect(isMarkedPresent(record(false, AttendanceSource.trainer)), isFalse);
    expect(isMarkedPresent(record(true, AttendanceSource.self)), isTrue);
  });
}
