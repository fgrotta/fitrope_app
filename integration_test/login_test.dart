import 'package:fitrope_app/pages/protected/Protected.dart';
import 'package:fitrope_app/pages/welcome/LoginPage.dart';
import 'package:fitrope_app/pages/welcome/WelcomePage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => assertCredentials(utenteBase1));

  testWidgets('Login: un utente valido accede e arriva alla pagina protetta',
      (tester) async {
    await launchTestApp(tester);

    // Dopo lo splash siamo sulla WelcomePage.
    expect(find.byType(WelcomePage), findsOneWidget);

    await login(tester, utenteBase1);

    // Login riuscito → siamo sulla pagina protetta (la LoginPage resta nello
    // stack sotto, perché si usa pushNamed e non pushReplacement).
    expect(find.byType(Protected), findsOneWidget);
  });

  testWidgets('Login: credenziali errate mostrano un messaggio di errore',
      (tester) async {
    await launchTestApp(tester);

    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login-email-field')), utenteBase1.email);
    await tester.enterText(
        find.byKey(const Key('login-password-field')), 'password-sbagliata');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login-submit-button')));

    // Restiamo sulla LoginPage e compare l'errore.
    await pumpUntilFound(tester, find.text('Email o password sbagliati'));
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
