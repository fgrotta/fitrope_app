import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/course_management_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser actor(String role, String uid) => FitropeUser(
      uid: uid,
      email: '$uid@example.com',
      name: role,
      lastName: 'Test',
      courses: const [],
      role: role,
      createdAt: DateTime(2026),
    );

Future<void> pumpPage(WidgetTester tester, CourseManagementPage page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

void main() {
  testWidgets('User diretto non renderizza il form corso', (tester) async {
    store.dispatch(SetUserAction(actor('User', 'user')));
    await pumpPage(tester, const CourseManagementPage(mode: 'create'));
    expect(find.byKey(const Key('course-form-access-denied')), findsOneWidget);
    expect(find.byKey(const Key('course-form-name-field')), findsNothing);
  });

  testWidgets('Trainer non modifica un corso assegnato a un altro trainer',
      (tester) async {
    store.dispatch(SetUserAction(actor('Trainer', 'trainer-a')));
    final start = DateTime.now().add(const Duration(days: 2));
    final course = Course(
      id: 'course', // ignore: deprecated_member_use_from_same_package
      uid: 'course',
      name: 'Altro trainer',
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
      capacity: 10,
      subscribed: 0,
      trainerId: 'trainer-b',
    );
    await pumpPage(
      tester,
      CourseManagementPage(mode: 'edit', courseToEdit: course),
    );
    expect(find.byKey(const Key('course-form-access-denied')), findsOneWidget);
    expect(find.byKey(const Key('course-form-name-field')), findsNothing);
  });
}
