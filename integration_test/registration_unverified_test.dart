import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/test_app.dart';

const signupEmail = String.fromEnvironment('SIGNUP_TEST_EMAIL');
const signupPassword = String.fromEnvironment('SIGNUP_TEST_PASSWORD');

Future<void> enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (signupEmail.isEmpty || signupPassword.length < 6) {
      throw StateError('SIGNUP_TEST_EMAIL/PASSWORD mancanti o non validi.');
    }
  });

  testWidgets('Registrazione crea la prova e blocca il login non verificato', (
    tester,
  ) async {
    await launchTestApp(tester);
    await tester.tap(find.byKey(const Key('welcome-registration-button')));
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('registration-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text("L'email non è valida"), findsOneWidget);
    expect(find.text('Devi accettare la privacy policy'), findsOneWidget);

    await enter(tester, 'registration-email-field', signupEmail);
    await enter(tester, 'registration-password-field', '12345');
    await enter(tester, 'registration-confirm-password-field', 'diversa');
    await enter(tester, 'registration-name-field', 'E');
    await enter(tester, 'registration-last-name-field', 'S');
    await enter(tester, 'registration-phone-field', '12345');
    await tester.tap(find.byKey(const Key('registration-privacy-checkbox')));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.text('La password deve essere lunga almeno 6 caratteri'),
      findsOneWidget,
    );
    expect(find.text('Il nome non è valido'), findsOneWidget);
    expect(find.text('Il cognome non è valido'), findsOneWidget);
    expect(
      find.text('Il numero di telefono deve contenere esattamente 10 cifre'),
      findsOneWidget,
    );

    await enter(tester, 'registration-password-field', signupPassword);
    await enter(
      tester,
      'registration-confirm-password-field',
      'password-diversa',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Le password devono essere uguali'), findsWidgets);

    await enter(tester, 'registration-confirm-password-field', signupPassword);
    await enter(tester, 'registration-name-field', 'E2E');
    await enter(tester, 'registration-last-name-field', 'Signup');
    await enter(tester, 'registration-phone-field', '3331234567');
    await tester.ensureVisible(submit);
    await tester.tap(submit);

    await pumpUntilFound(tester, find.text('Email di conferma inviata!'));
    final authUser = FirebaseAuth.instance.currentUser;
    expect(authUser, isNotNull);
    expect(authUser!.emailVerified, isFalse);

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid)
        .get();
    final data = doc.data();
    expect(data, isNotNull);
    expect(data!['role'], 'User');
    expect(data['tipologiaIscrizione'], 'ABBONAMENTO_PROVA');
    expect(data['entrateDisponibili'], 1);
    expect(data['tipologiaCorsoTags'], ['Open']);
    final expiry = (data['fineIscrizione'] as Timestamp).toDate();
    expect(expiry.difference(DateTime.now()).inDays, inInclusiveRange(29, 30));

    await tester.tap(
      find.byKey(const Key('registration-success-login-button')),
    );
    await tester.pumpAndSettle();
    await enter(tester, 'login-email-field', signupEmail);
    await enter(tester, 'login-password-field', signupPassword);
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await pumpUntilFound(tester, find.textContaining('Email non verificata'));
    expect(
      find.byKey(const Key('login-resend-verification-button')),
      findsOneWidget,
    );
  });
}
