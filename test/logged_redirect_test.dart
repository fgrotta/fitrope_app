import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/authentication/is_logged.dart';
import 'package:fitrope_app/router.dart';

/// Al reload su `/#/protected` il Navigator costruisce `['/', '/protected']`:
/// la Welcome sotto, per un utente loggato, chiamava `loggedRedirect` e
/// sostituiva il `Protected` appena montato con un secondo (doppio
/// `getUserData`, doppio login OneSignal a ogni reload).
class _WelcomeLike extends StatefulWidget {
  const _WelcomeLike();

  @override
  State<_WelcomeLike> createState() => _WelcomeLikeState();
}

class _WelcomeLikeState extends State<_WelcomeLike> {
  @override
  void initState() {
    super.initState();
    // Come WelcomePage con isLogged() == true.
    loggedRedirect(context);
  }

  @override
  Widget build(BuildContext context) => const Text('welcome');
}

class _CountingProtected extends StatefulWidget {
  const _CountingProtected(this.onMount);
  final VoidCallback onMount;

  @override
  State<_CountingProtected> createState() => _CountingProtectedState();
}

class _CountingProtectedState extends State<_CountingProtected> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('protected');
}

void main() {
  Future<int> pumpAt(WidgetTester tester, String initialRoute) async {
    var mounts = 0;
    await tester.pumpWidget(MaterialApp(
      initialRoute: initialRoute,
      routes: {
        WELCOME_ROUTE: (_) => const _WelcomeLike(),
        PROTECTED_ROUTE: (_) => _CountingProtected(() => mounts++),
      },
    ));
    await tester.pumpAndSettle();
    return mounts;
  }

  testWidgets('reload su /protected: un solo Protected', (tester) async {
    expect(await pumpAt(tester, PROTECTED_ROUTE), 1);
  });

  testWidgets('Welcome in cima con utente loggato: redirect all\'area protetta',
      (tester) async {
    expect(await pumpAt(tester, WELCOME_ROUTE), 1);
    expect(find.text('protected'), findsOneWidget);
  });
}
