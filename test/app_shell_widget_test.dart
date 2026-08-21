import 'package:fitrope_app/layout/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpShell(
  WidgetTester tester, {
  required bool isAdmin,
  double width = 1200,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: AppShell(
          currentIndex: 0,
          isAdmin: isAdmin,
          onChangePage: (_) {},
          child: const Text('contenuto'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desktop Admin vede Utenti e Dashboard', (tester) async {
    await pumpShell(tester, isAdmin: true);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(find.byKey(const Key('nav-calendar')), findsOneWidget);
    expect(find.byKey(const Key('nav-users')), findsOneWidget);
    expect(find.byKey(const Key('nav-dashboard')), findsOneWidget);
  });

  testWidgets('desktop non Admin non vede destinazioni amministrative',
      (tester) async {
    await pumpShell(tester, isAdmin: false);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(find.byKey(const Key('nav-calendar')), findsOneWidget);
    expect(find.byKey(const Key('nav-users')), findsNothing);
    expect(find.byKey(const Key('nav-dashboard')), findsNothing);
  });

  testWidgets('su mobile la dashboard non viene mai proposta', (tester) async {
    await pumpShell(tester, isAdmin: true, width: 500);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Calendario'), findsOneWidget);
    expect(find.text('Utenti'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });
}
