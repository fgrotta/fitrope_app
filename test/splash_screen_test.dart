import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/pages/welcome/splash_screen.dart';
import 'package:fitrope_app/router.dart';

/// `initialRoute: '/splash'` fa costruire al Navigator anche `'/'` sotto lo
/// splash, e la Welcome per un utente loggato fa già `pushReplacementNamed`
/// verso l'area protetta. Senza più i 2 s di attesa lo splash arriva mentre è
/// ancora `mounted` (la sua route sta animando l'uscita) e spingeva un SECONDO
/// `Protected`: doppio mount, doppio `getUserData`.
class _RedirectingWelcome extends StatefulWidget {
  const _RedirectingWelcome({required this.loggedIn});
  final bool loggedIn;

  @override
  State<_RedirectingWelcome> createState() => _RedirectingWelcomeState();
}

class _RedirectingWelcomeState extends State<_RedirectingWelcome> {
  @override
  void initState() {
    super.initState();
    // Come WelcomePage.initState → loggedRedirect.
    if (widget.loggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(PROTECTED_ROUTE);
      });
    }
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
  Future<int> pumpApp(WidgetTester tester, {required bool loggedIn}) async {
    var protectedMounts = 0;
    await tester.pumpWidget(MaterialApp(
      initialRoute: SPLASH_ROUTE,
      routes: {
        WELCOME_ROUTE: (_) => _RedirectingWelcome(loggedIn: loggedIn),
        SPLASH_ROUTE: (_) => SplashScreen(
              authReady: () async {},
              isLoggedIn: () => loggedIn,
            ),
        PROTECTED_ROUTE: (_) => _CountingProtected(() => protectedMounts++),
      },
    ));
    await tester.pumpAndSettle();
    return protectedMounts;
  }

  testWidgets('utente loggato: Protected montato una volta sola',
      (tester) async {
    expect(await pumpApp(tester, loggedIn: true), 1);
    expect(find.text('protected'), findsOneWidget);
  });

  testWidgets('visitatore: arriva alla Welcome senza attese', (tester) async {
    expect(await pumpApp(tester, loggedIn: false), 0);
    expect(find.text('welcome'), findsOneWidget);
  });
}
