import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/api/courses/get_attendance.dart';
import 'package:fitrope_app/components/attendance_toggle.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser _user(String uid, String role, {List<String> courses = const []}) =>
    FitropeUser(
      uid: uid,
      name: 'Nome',
      lastName: uid,
      email: '$uid@example.com',
      courses: courses,
      role: role,
      createdAt: DateTime(2026, 1, 1),
    );

Course _course(DateTime start) => Course(
      id: 'c1',
      uid: 'c1',
      name: 'Corso',
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
      capacity: 10,
      subscribed: 1,
      trainerId: 't1',
    );

Future<void> _pumpCard(
  WidgetTester tester,
  Course course,
  FirebaseFirestore db, {
  bool withToggleHandler = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CoursePreviewCard(
          course: course,
          currentUser: _user('t1', 'Trainer'),
          trainers: const [],
          onRefresh: () {},
          onToggleAttendance: withToggleHandler ? (_, __) async => true : null,
          firestore: db,
        ),
      ),
    ),
  ));
}

Future<void> _settleFirestore(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50),
      ));
  await tester.pump();
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    invalidateAttendanceCache();
    db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc('u1')
        .set(_user('u1', 'User', courses: ['c1']).toJson());
  });

  testWidgets(
      'lista aperta prima di -30\': al confine le presenze si caricano '
      '(niente spinner eterni)', (tester) async {
    // Il confine staff (-30') cade tra 5 secondi.
    final start = DateTime.now().add(
      const Duration(minutes: 30, seconds: 5),
    );
    await _pumpCard(tester, _course(start), db);
    await _settleFirestore(tester);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.byType(AttendanceToggle), findsNothing); // fuori finestra

    // Tempo reale oltre il confine, poi il Timer (orologio finto) scatta.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pump(const Duration(seconds: 10));
    await _settleFirestore(tester);

    final chip = tester.widget<AttendanceToggle>(find.byType(AttendanceToggle));
    expect(chip.pending, isFalse, reason: 'chip ancora in attesa');
  });

  testWidgets(
      'staff su una pagina senza appello (home): niente spunte disabilitate',
      (tester) async {
    await _pumpCard(
      tester,
      _course(DateTime.now().subtract(const Duration(minutes: 5))),
      db,
      withToggleHandler: false,
    );
    await _settleFirestore(tester);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    await _settleFirestore(tester);
    expect(find.byType(AttendanceToggle), findsNothing);
  });
}
