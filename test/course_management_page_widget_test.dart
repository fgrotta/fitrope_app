import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/course_management_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser staffUser({String role = 'Admin'}) => FitropeUser(
      uid: role.toLowerCase(),
      email: '${role.toLowerCase()}@example.com',
      name: role,
      lastName: 'Test',
      courses: const [],
      role: role,
      createdAt: DateTime(2026),
    );

Future<void> pumpCourseForm(
  WidgetTester tester, {
  String mode = 'create',
  Course? courseToEdit,
  required Future<Course?> Function(Course) create,
  Future<void> Function(Course)? update,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CourseManagementPage(
        mode: mode,
        courseToEdit: courseToEdit,
        loadTrainers: () async => [],
        createCourseOperation: create,
        updateCourseOperation: update ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapCourseSubmit(WidgetTester tester) async {
  final submit = find.byKey(const Key('course-form-submit-button'));
  tester.widget<ElevatedButton>(submit).onPressed!.call();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => store.dispatch(SetUserAction(staffUser())));

  testWidgets('create valida nome, durata e capacità', (tester) async {
    await pumpCourseForm(tester, create: (_) async => null);
    await tapCourseSubmit(tester);
    expect(find.text('Il nome del corso è obbligatorio'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('course-form-name-field')),
      'Open serale',
    );
    await tester.enterText(
      find.byKey(const Key('course-form-capacity-field')),
      '0',
    );
    await tapCourseSubmit(tester);
    expect(
      find.text('Il numero di partecipanti deve essere maggiore di 0'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('course-form-capacity-field')),
      '6',
    );
    await tester.enterText(
      find.byKey(const Key('course-form-duration-field')),
      '0',
    );
    await tapCourseSubmit(tester);
    expect(find.text('La durata deve essere maggiore di 0'), findsOneWidget);
  });

  testWidgets('create inoltra default sicuri e flag selezionati',
      (tester) async {
    Course? captured;
    await pumpCourseForm(
      tester,
      create: (course) async {
        captured = course;
        return course;
      },
    );

    await tester.enterText(
      find.byKey(const Key('course-form-name-field')),
      'Corso widget',
    );
    final reminder = find.byKey(const Key('course-form-reminder-switch'));
    await tester.ensureVisible(reminder);
    await tester.tap(reminder);
    await tapCourseSubmit(tester);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.name, 'Corso widget');
    expect(captured!.capacity, 6);
    expect(captured!.subscribed, 0);
    expect(captured!.startDate.toDate().isAfter(DateTime.now()), isTrue);
    expect(captured!.reminderEnabled, isFalse);
    expect(captured!.waitlistEnabled, isTrue);
  });

  testWidgets('Trainer è auto-assegnato e non vede il dropdown trainer',
      (tester) async {
    store.dispatch(SetUserAction(staffUser(role: 'Trainer')));
    Course? captured;
    await pumpCourseForm(
      tester,
      create: (course) async {
        captured = course;
        return course;
      },
    );
    expect(find.byKey(const Key('course-form-trainer-dropdown')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('course-form-name-field')),
      'Corso trainer',
    );
    await tapCourseSubmit(tester);
    await tester.pumpAndSettle();
    expect(captured?.trainerId, 'trainer');
  });

  testWidgets('edit nasconde durata e preserva campi server-owned nel modello',
      (tester) async {
    final start = DateTime.now().add(const Duration(days: 2));
    final original = Course(
      id: 'course-1', // ignore: deprecated_member_use_from_same_package
      uid: 'course-1',
      name: 'Originale',
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
      capacity: 8,
      subscribed: 3,
      waitlist: const ['wait-1'],
    );
    Course? updated;
    await pumpCourseForm(
      tester,
      mode: 'edit',
      courseToEdit: original,
      create: (_) async => null,
      update: (course) async => updated = course,
    );
    expect(find.byKey(const Key('course-form-duration-field')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('course-form-name-field')),
      'Modificato',
    );
    await tapCourseSubmit(tester);
    await tester.pumpAndSettle();
    expect(updated?.uid, 'course-1');
    expect(updated?.subscribed, 3);
    expect(updated?.waitlist, ['wait-1']);
  });
}
