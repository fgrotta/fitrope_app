import 'package:fitrope_app/api/courses/enrollment_callable.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/utils/simulation_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Layer A (`SimulationGuard`, la protezione che l'admin *vede*) e il choke
/// point delle callable enrollment — le due superfici che
/// `simulation_guard_test.dart` non tocca, nonostante il nome.
void main() {
  final admin = simUser(uid: 'admin-1', role: 'Admin');
  final target = simUser(uid: 'user-1', role: 'User');

  tearDown(() {
    SimulationSession.stop();
    store.dispatch(FinishLoadingAction());
  });

  group('SimulationGuard.blockIfSimulating', () {
    /// Monta un bottone che registra se il corpo del callback è stato eseguito,
    /// cioè la stessa forma usata dai call site nelle pagine.
    Future<bool> tapAzione(WidgetTester tester) async {
      var eseguita = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                if (SimulationGuard.blockIfSimulating(context)) return;
                eseguita = true;
              },
              child: const Text('Iscriviti'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Iscriviti'));
      await tester.pump();
      return eseguita;
    }

    testWidgets('a simulazione spenta lascia passare e non mostra nulla',
        (tester) async {
      expect(await tapAzione(tester), isTrue);
      expect(find.text(kSimulationBlockedMessage), findsNothing);
    });

    testWidgets('in simulazione blocca il corpo del callback', (tester) async {
      SimulationSession.start(admin: admin, target: target);

      // Se il booleano di ritorno venisse invertito, l'azione proseguirebbe
      // fino al Layer B e l'admin vedrebbe uno snackbar ROSSO di errore al
      // posto del messaggio previsto.
      expect(await tapAzione(tester), isFalse);
    });

    testWidgets('mostra lo snackbar di warning (arancione), non di errore',
        (tester) async {
      SimulationSession.start(admin: admin, target: target);

      await tapAzione(tester);
      await tester.pump(); // animazione di entrata dello snackbar

      expect(find.text(kSimulationBlockedMessage), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, Colors.orange);
    });
  });

  group('callEnrollmentFunction (choke point di 6 callable)', () {
    test('in simulazione lancia prima di toccare FirebaseFunctions', () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        callEnrollmentFunction(
          'subscribeToCourse',
          {'courseId': 'c1', 'userId': target.uid},
          userId: target.uid,
          fallbackError: 'errore',
        ),
        throwsA(isA<SimulationBlockedException>()),
      );
    });

    test(
        'la guardia sta PRIMA di StartLoadingAction: isLoading resta false '
        '(altrimenti il Loader copre l\'app per sempre)', () async {
      store.dispatch(FinishLoadingAction());
      SimulationSession.start(admin: admin, target: target);

      try {
        await callEnrollmentFunction(
          'deleteCourse',
          {'courseId': 'c1'},
          fallbackError: 'errore',
        );
      } on SimulationBlockedException {
        // atteso
      }

      // Il `finally` con FinishLoadingAction sta DENTRO il try: se la guardia
      // scivolasse di una riga sotto `StartLoadingAction`, il throw uscirebbe
      // prima del try e isLoading resterebbe true per sempre.
      expect(store.state.isLoading, isFalse);
    });
  });
}
