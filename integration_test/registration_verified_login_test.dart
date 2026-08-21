import 'package:fitrope_app/pages/protected/protected.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/test_app.dart';

const signupEmail = String.fromEnvironment('SIGNUP_TEST_EMAIL');
const signupPassword = String.fromEnvironment('SIGNUP_TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (signupEmail.isEmpty || signupPassword.length < 6) {
      throw StateError('SIGNUP_TEST_EMAIL/PASSWORD mancanti o non validi.');
    }
  });

  testWidgets(
    'Login riesce dopo la verifica amministrativa della stessa email',
    (tester) async {
      await launchTestApp(tester);
      await tester.tap(find.byKey(const Key('welcome-login-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login-email-field')),
        signupEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login-password-field')),
        signupPassword,
      );
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await pumpUntilFound(tester, find.byType(Protected));
    },
  );
}
