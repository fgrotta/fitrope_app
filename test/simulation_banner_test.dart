import 'package:fitrope_app/components/simulation_banner.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

void main() {
  tearDown(SimulationSession.stop);

  final admin = simUser(uid: 'admin-1', role: 'Admin');
  final target =
      simUser(uid: 'user-1', role: 'User', name: 'Mario', lastName: 'Rossi');

  Future<void> pump(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: SimulationBanner(
          child: Scaffold(body: Center(child: Text('contenuto'))),
        ),
      ),
    );
  }

  testWidgets('a simulazione spenta il child è renderizzato intatto',
      (tester) async {
    await pump(tester, size: const Size(1200, 800));

    expect(find.text('contenuto'), findsOneWidget);
    expect(find.text('Esci dalla simulazione'), findsNothing);
    // Nessun wrapper aggiunto: il child è figlio diretto del builder.
    expect(find.byType(Column), findsNothing);
  });

  testWidgets('in simulazione mostra nome e uscita, senza perdere il child',
      (tester) async {
    SimulationSession.start(admin: admin, target: target);
    await pump(tester, size: const Size(1200, 800));

    expect(find.text('Stai visualizzando l\'app come Mario Rossi'),
        findsOneWidget);
    expect(find.text('Esci dalla simulazione'), findsOneWidget);
    expect(find.text('contenuto'), findsOneWidget);
  });

  testWidgets('sotto i 600 l\'uscita esiste ancora, in variante icon-only',
      (tester) async {
    SimulationSession.start(admin: admin, target: target);
    await pump(tester, size: const Size(420, 800));

    // La label lunga sparisce, ma il bottone di uscita NON deve mai essere
    // troncato via: resta raggiungibile come icona con tooltip.
    expect(find.text('Esci dalla simulazione'), findsNothing);
    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Esci dalla simulazione'),
      findsOneWidget,
    );
  });

  testWidgets('la barra compare e sparisce reagendo al notifier',
      (tester) async {
    await pump(tester, size: const Size(1200, 800));
    expect(find.text('Esci dalla simulazione'), findsNothing);

    SimulationSession.start(admin: admin, target: target);
    await tester.pump();
    expect(find.text('Esci dalla simulazione'), findsOneWidget);

    SimulationSession.stop();
    await tester.pump();
    expect(find.text('Esci dalla simulazione'), findsNothing);
    expect(find.text('contenuto'), findsOneWidget);
  });
}
