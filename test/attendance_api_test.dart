import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/api/courses/enrollment_callable.dart';
import 'package:fitrope_app/api/courses/get_attendance.dart';
import 'package:fitrope_app/api/courses/set_attendance.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> rec(String courseId, String userId,
        {bool present = true, String source = 'self'}) =>
    {
      'courseId': courseId,
      'userId': userId,
      'courseStartMillis': 0,
      'present': present,
      'source': source,
    };

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    invalidateAttendanceCache();
  });

  group('getCourseAttendance', () {
    test('mappa uid → record dei soli doc del corso', () async {
      await db.collection('attendance').doc('c1_u1').set(rec('c1', 'u1'));
      await db
          .collection('attendance')
          .doc('c1_u2')
          .set(rec('c1', 'u2', present: false, source: 'trainer'));
      await db.collection('attendance').doc('c2_u1').set(rec('c2', 'u1'));

      final byUser = await getCourseAttendance('c1', firestore: db);
      expect(byUser.keys.toSet(), {'u1', 'u2'});
      expect(byUser['u2']!.source, AttendanceSource.trainer);
      expect(byUser['u2']!.present, isFalse);
    });

    test('cache: seconda lettura dalla memoria, invalidate la svuota',
        () async {
      await db.collection('attendance').doc('c1_u1').set(rec('c1', 'u1'));
      expect((await getCourseAttendance('c1', firestore: db)).length, 1);

      await db.collection('attendance').doc('c1_u2').set(rec('c1', 'u2'));
      expect((await getCourseAttendance('c1', firestore: db)).length, 1);
      expect(
        (await getCourseAttendance('c1', firestore: db, force: true)).length,
        2,
      );

      await db.collection('attendance').doc('c1_u3').set(rec('c1', 'u3'));
      invalidateAttendanceCache();
      expect((await getCourseAttendance('c1', firestore: db)).length, 3);
    });
  });

  group('getMyAttendance', () {
    test('get sull\'id deterministico; null in cache anche lui', () async {
      expect(await getMyAttendance('c1', 'u1', firestore: db), isNull);
      // Il doc arriva dopo: la cache del null lo nasconde fino all'invalidate.
      await db.collection('attendance').doc('c1_u1').set(rec('c1', 'u1'));
      expect(await getMyAttendance('c1', 'u1', firestore: db), isNull);
      invalidateAttendanceCache();
      final mine = await getMyAttendance('c1', 'u1', firestore: db);
      expect(mine?.present, isTrue);
    });
  });

  group('attendanceErrorMessage', () {
    test('details.reason ha la precedenza sul messaggio', () {
      const e = EnrollmentException(
        'messaggio server',
        code: 'failed-precondition',
        details: {'reason': 'ATTENDANCE_WINDOW_CLOSED'},
      );
      expect(attendanceRejectReason(e), AttendanceRejectReason.windowClosed);
      expect(
        attendanceErrorMessage(e),
        'Check-in chiuso: chiedi al trainer di registrare la tua presenza',
      );
    });

    test('fallback: reason nel testo del messaggio', () {
      const e = EnrollmentException('x ATTENDANCE_NOT_COURSE_TRAINER y');
      expect(
        attendanceRejectReason(e),
        AttendanceRejectReason.notCourseTrainer,
      );
      expect(
        attendanceErrorMessage(e),
        'Puoi registrare le presenze solo dei tuoi corsi',
      );
    });

    test('testi italiani per i casi principali', () {
      String msg(String reason) => attendanceErrorMessage(
            EnrollmentException('m', details: {'reason': reason}),
          );
      expect(msg('ATTENDANCE_WINDOW_NOT_OPEN'),
          'La registrazione delle presenze non è ancora aperta');
      expect(msg('ATTENDANCE_ALREADY_RECORDED_BY_STAFF'),
          'Presenza già registrata dallo staff');
      expect(msg('ATTENDANCE_NOT_ENROLLED'),
          'L\'utente non è iscritto a questo corso');
    });

    test('reason sconosciuta o errore generico → messaggio originale', () {
      expect(
        attendanceRejectReason(const EnrollmentException('boh')),
        isNull,
      );
      expect(attendanceErrorMessage(const EnrollmentException('boh')), 'boh');
      expect(attendanceErrorMessage(Exception('rete')), contains('rete'));
    });
  });
}
