import 'package:fitrope_app/pages/protected/protected.dart';
import 'package:fitrope_app/pages/welcome/welcome_page.dart';
import 'package:fitrope_app/pages/welcome/registration_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/test_app.dart';

/// Entry point unico E2E. Le fixture non sono create dal client: lo fa il
/// control plane Admin SDK prima del drive e le assert/cleanup dopo il drive.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const memberEmail = String.fromEnvironment('E2E_MEMBER_EMAIL');
  const waiterEmail = String.fromEnvironment('E2E_WAITER_EMAIL');
  const password = String.fromEnvironment('E2E_PASSWORD');
  const courseId = String.fromEnvironment('E2E_COURSE_ID');
  const registrationEmail = String.fromEnvironment('E2E_REGISTRATION_EMAIL');
  const legacyEmail = String.fromEnvironment('E2E_LEGACY_EMAIL');
  const legacyCourseId = String.fromEnvironment('E2E_LEGACY_COURSE_ID');

  testWidgets('E2E: utente fixture accede all’app reale', (tester) async {
    expect(memberEmail, isNotEmpty);
    expect(password, isNotEmpty);
    await launchTestApp(tester);
    expect(find.byType(WelcomePage), findsOneWidget);
    await login(
      tester,
      const TestUser(email: memberEmail, password: password, role: 'User'),
    );
    expect(find.byType(Protected), findsOneWidget);
    await openCalendarTab(tester);
    await selectE2eCourseDate(tester);
    await expectCourseAction(tester, courseId, 'Prenotati');
    await tapCourseAction(tester, courseId);
    await expectCourseAction(tester, courseId, 'Rimuovi iscrizione');
    await logoutAndRestart(tester);
    await login(
      tester,
      const TestUser(email: waiterEmail, password: password, role: 'User'),
    );
    await openCalendarTab(tester);
    await selectE2eCourseDate(tester);
    await expectCourseAction(tester, courseId, "Lista d'attesa");
    await tapCourseAction(tester, courseId);
    // L'iscrizione alla lista d'attesa richiede una conferma esplicita nel
    // dialog mostrato dall'app; il tap precedente apre il dialog, non invia
    // ancora la callable.
    await confirmDialog(tester, 'Conferma');
    await expectCourseAction(tester, courseId, "Esci dalla lista d'attesa");
    await logoutAndRestart(tester);
    await login(
      tester,
      const TestUser(email: memberEmail, password: password, role: 'User'),
    );
    await openCalendarTab(tester);
    await selectE2eCourseDate(tester);
    await tapCourseAction(tester, courseId);
    await expectCourseAction(tester, courseId, 'Prenotati');
    await logoutAndRestart(tester);
    await login(
      tester,
      const TestUser(email: waiterEmail, password: password, role: 'User'),
    );
    await openCalendarTab(tester);
    await selectE2eCourseDate(tester);
    await expectCourseAction(
      tester,
      courseId,
      'Posto disponibile! Iscriviti ora',
    );
    await tapCourseAction(tester, courseId);
    await expectCourseAction(tester, courseId, 'Rimuovi iscrizione');
  });

  testWidgets('E2E: registrazione crea prova e conferma email', (tester) async {
    expect(registrationEmail, isNotEmpty);
    await launchTestApp(tester);
    await tester.tap(find.text('Registrati'));
    await tester.pumpAndSettle();
    expect(find.byType(RegistrationPage), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('registration-email-field')), registrationEmail);
    await tester.enterText(
        find.byKey(const Key('registration-password-field')), 'E2e-test-123!');
    await tester.enterText(
        find.byKey(const Key('registration-confirm-password-field')),
        'E2e-test-123!');
    await tester.enterText(
        find.byKey(const Key('registration-name-field')), 'E2E');
    await tester.enterText(
        find.byKey(const Key('registration-last-name-field')), 'Registration');
    await tester.tap(find.byKey(const Key('registration-privacy-checkbox')));
    await tester.tap(find.byKey(const Key('registration-submit-button')));
    await pumpUntilFound(tester, find.text('Email di conferma inviata!'));
    final registered = FirebaseAuth.instance.currentUser;
    expect(registered, isNotNull);
    final uid = registered!.uid;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    expect(userDoc.data()?['tipologiaIscrizione'], 'ABBONAMENTO_PROVA');
    expect(userDoc.data()?['role'], 'User');
    await registered.delete();
  });

  testWidgets('E2E: pacchetto legacy scala e rimborsa un ingresso',
      (tester) async {
    expect(legacyEmail, isNotEmpty);
    await launchTestApp(tester);
    await login(tester,
        const TestUser(email: legacyEmail, password: password, role: 'User'));
    await openCalendarTab(tester);
    await selectE2eCourseDate(tester);
    await expectCourseAction(tester, legacyCourseId, 'Prenotati');
    await tapCourseAction(tester, legacyCourseId);
    await expectCourseAction(tester, legacyCourseId, 'Rimuovi iscrizione');
    await tapCourseAction(tester, legacyCourseId);
    await expectCourseAction(tester, legacyCourseId, 'Prenotati');
  });
}
