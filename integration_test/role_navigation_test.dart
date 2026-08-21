import 'package:fitrope_app/pages/protected/course_management_page.dart';
import 'package:fitrope_app/pages/protected/protected.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    assertCredentials(adminTest);
    assertCredentials(trainerTest);
    assertCredentials(utenteBase1);
  });

  testWidgets('Ruoli: navigazione e accesso diretto rispettano i permessi',
      (tester) async {
    await launchTestApp(tester);
    await login(tester, utenteBase1);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(find.byKey(const Key('nav-calendar')), findsOneWidget);
    expect(find.byKey(const Key('nav-users')), findsNothing);
    expect(find.byKey(const Key('nav-dashboard')), findsNothing);

    final navigator = Navigator.of(tester.element(find.byType(Protected)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const CourseManagementPage(mode: 'create'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('course-form-name-field')), findsNothing);

    await logoutAndRestart(tester);
    await login(tester, trainerTest);
    expect(find.byKey(const Key('nav-users')), findsNothing);
    expect(find.byKey(const Key('nav-dashboard')), findsNothing);
    await openCalendarTab(tester);
    expect(
      find.byKey(const Key('calendar-create-course-button')),
      findsOneWidget,
    );

    await logoutAndRestart(tester);
    await login(tester, adminTest);
    expect(find.byKey(const Key('nav-users')), findsOneWidget);
    expect(find.byKey(const Key('nav-dashboard')), findsOneWidget);
  });
}
