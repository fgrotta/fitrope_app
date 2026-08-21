import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/seed.dart';
import 'helpers/test_app.dart';

Future<void> tapInLongForm(WidgetTester tester, Finder finder) async {
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 12; attempt++) {
    final y = tester.getCenter(finder).dy;
    if (y > 60 && y < height - 60) break;
    await tester.drag(
      find.byType(SingleChildScrollView),
      Offset(0, y >= height - 60 ? -500 : 500),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> waitForCourses(
  WidgetTester tester,
  String name, {
  int minimum = 1,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await FirebaseFirestore.instance
        .collection('courses')
        .where('name', isEqualTo: name)
        .get();
    if (snapshot.docs.length >= minimum) return snapshot.docs;
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw StateError('Corsi "$name" non creati entro il timeout.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => assertCredentials(adminTest));

  testWidgets('Gestione corsi: creazione singola e ricorrente via UI',
      (tester) async {
    final createdIds = <String>[];
    addTearDown(() async {
      for (final id in createdIds) {
        await deleteTestCourseAsAdmin(
          courseId: id,
          adminEmail: adminTest.email,
          adminPassword: adminTest.password,
        );
      }
    });

    await launchTestApp(tester);
    await login(tester, adminTest);
    await openCalendarTab(tester);

    final singleName = '[TEST:$testRunNamespace] UI corso singolo';
    await tester.tap(find.byKey(const Key('calendar-create-course-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('course-form-name-field')),
      singleName,
    );
    await tapInLongForm(
      tester,
      find.byKey(const Key('course-form-reminder-switch')),
    );
    await tapInLongForm(
      tester,
      find.byKey(const Key('course-form-submit-button')),
    );
    final single = await waitForCourses(tester, singleName);
    createdIds.addAll(single.map((doc) => doc.id));
    expect(single, hasLength(1));
    expect(single.single.data()['reminderEnabled'], isFalse);
    expect(single.single.data()['subscribed'], 0);

    final recurringName = '[TEST:$testRunNamespace] UI corso ricorrente';
    await pumpUntilFound(
      tester,
      find.byKey(const Key('calendar-recurring-course-button')),
    );
    await tester.tap(
      find.byKey(const Key('calendar-recurring-course-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recurring-course-name-field')),
      recurringName,
    );
    final tomorrowWeekday = DateTime.now().add(const Duration(days: 1)).weekday;
    await tapInLongForm(
      tester,
      find.byKey(Key('recurring-course-weekday-$tomorrowWeekday')),
    );
    await tapInLongForm(
      tester,
      find.byKey(const Key('recurring-course-reminder-switch')),
    );
    await tapInLongForm(
      tester,
      find.byKey(const Key('recurring-course-submit-button')),
    );
    final recurring = await waitForCourses(tester, recurringName, minimum: 4);
    createdIds.addAll(recurring.map((doc) => doc.id));
    expect(recurring.length, greaterThanOrEqualTo(4));
    expect(
      recurring.every((doc) => doc.data()['reminderEnabled'] == false),
      isTrue,
    );
  });
}
