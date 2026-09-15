import 'dart:async';

import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/refresh_current_user.dart';
import 'package:fitrope_app/utils/simulation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Copre `SimulationController` **eseguendolo**, non ri-implementandone la
/// sequenza: è il pezzo che tiene insieme sessione, store e remount, ed è lo
/// stesso file in cui un bug (Navigator.of dalla barra) è già arrivato fino al
/// QA manuale.
///
/// Senza `appNavigatorKey` montata `_remount()` si limita a loggare e uscire:
/// questo permette di verificare sessione e store senza caricare le route
/// deferred dell'app.
void main() {
  // `appNavigatorKey.currentState` passa da WidgetsBinding.instance: senza
  // binding inizializzato `_remount` esplode invece di uscire con il debugPrint.
  TestWidgetsFlutterBinding.ensureInitialized();

  final admin = simUser(uid: 'admin-1', role: 'Admin', name: 'Anna');
  final target = simUser(uid: 'user-1', role: 'User', name: 'Mario');

  tearDown(() {
    SimulationSession.stop();
    store.dispatch(SetUserAction(null));
    store.dispatch(FinishLoadingAction());
  });

  /// Porta lo store e la sessione nello stato "simulazione in corso", come li
  /// lascerebbe `start()`.
  void inSimulazione() {
    store.dispatch(SetUserAction(admin));
    SimulationSession.start(admin: admin, target: target);
    store.dispatch(SetUserAction(target));
  }

  Future<void> pumpStartButton(
    WidgetTester tester, {
    required Future<FitropeUser?> Function(String uid) loadTarget,
    Size size = const Size(800, 600),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SimulationController.start(
                  context,
                  target: target,
                  loadTarget: loadTarget,
                ),
                child: const Text('Avvia'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('SimulationController.start', () {
    testWidgets('usa lo snapshot fresco restituito dal server', (tester) async {
      store.dispatch(SetUserAction(admin));
      final freshTarget =
          simUser(uid: target.uid, role: 'User', name: 'Mario aggiornato');
      await pumpStartButton(
        tester,
        loadTarget: (_) async => freshTarget,
      );

      await tester.tap(find.text('Avvia'));
      await tester.pump();

      expect(SimulationSession.isActive, isTrue);
      expect(SimulationSession.current.value!.simulatedUser.name,
          'Mario aggiornato');
      expect(store.state.user, same(freshTarget));
      expect(store.state.isLoading, isFalse);
    });

    testWidgets('start su layout mobile (360x640) attiva la sessione',
        (tester) async {
      // Regressione del gate rimosso: finché `canSimulateUser` prendeva
      // `isMobileLayout`, questo tap finiva nello snackbar di precondizione
      // invece che in simulazione.
      store.dispatch(SetUserAction(admin));
      await pumpStartButton(
        tester,
        loadTarget: (_) async => target,
        size: const Size(360, 640),
      );

      await tester.tap(find.text('Avvia'));
      await tester.pump();

      expect(SimulationSession.isActive, isTrue);
      expect(store.state.user, same(target));
      expect(store.state.isLoading, isFalse);
    });

    testWidgets('rivalida l\'identità admin dopo il caricamento',
        (tester) async {
      store.dispatch(SetUserAction(admin));
      final response = Completer<FitropeUser?>();
      await pumpStartButton(
        tester,
        loadTarget: (_) => response.future,
      );

      await tester.tap(find.text('Avvia'));
      await tester.pump();
      expect(store.state.isLoading, isTrue);

      final anotherAdmin =
          simUser(uid: 'admin-2', role: 'Admin', name: 'Beatrice');
      store.dispatch(SetUserAction(anotherAdmin));
      response.complete(target);
      await tester.pump();

      expect(SimulationSession.isActive, isFalse);
      expect(store.state.user, same(anotherAdmin));
      expect(store.state.isLoading, isFalse);
      expect(find.text('Simulazione non più disponibile per questo utente'),
          findsOneWidget);
    });

    testWidgets('un errore di caricamento non attiva la sessione né il Loader',
        (tester) async {
      store.dispatch(SetUserAction(admin));
      await pumpStartButton(
        tester,
        loadTarget: (_) =>
            Future.error(StateError('Firestore non disponibile')),
      );

      await tester.tap(find.text('Avvia'));
      await tester.pump();

      expect(SimulationSession.isActive, isFalse);
      expect(store.state.user, same(admin));
      expect(store.state.isLoading, isFalse);
      expect(find.text('Impossibile caricare i dati aggiornati dell\'utente'),
          findsOneWidget);
    });
  });

  group('SimulationController.stop', () {
    test('ripristina l\'admin dallo snapshot e chiude la sessione', () {
      inSimulazione();
      expect(store.state.user!.uid, target.uid);

      SimulationController.stop();

      expect(store.state.user!.uid, admin.uid);
      expect(store.state.user!.role, 'Admin');
      expect(SimulationSession.isActive, isFalse);
      expect(SimulationSession.current.value, isNull);
    });

    test('senza Navigator montato NON lascia il Loader acceso', () {
      // È il ramo di `_remount()` che esce presto: `StartLoadingAction` è già
      // stato dispatchato, quindi il Finish va garantito anche qui, altrimenti
      // `isLoading` resta true per sempre e il Loader copre l'app.
      inSimulazione();

      SimulationController.stop();

      expect(store.state.isLoading, isFalse);
    });

    test('a sessione spenta è un no-op e non tocca lo store', () {
      store.dispatch(SetUserAction(admin));
      var notifiche = 0;
      void listener() => notifiche++;
      SimulationSession.current.addListener(listener);
      addTearDown(() => SimulationSession.current.removeListener(listener));

      SimulationController.stop();

      expect(notifiche, 0);
      expect(store.state.user!.uid, admin.uid);
    });
  });

  group('race all\'uscita (blocker: guardie disarmate + utente simulato)', () {
    test('un refresh in volo sul socio NON reinstalla il socio dopo l\'uscita',
        () {
      inSimulazione();

      // La vecchia HomePage resta montata per tutta la transizione di
      // pushNamedAndRemoveUntil (~300ms): il suo `getUserData(socio)` può
      // tornare DOPO lo stop. Con un dispatch diretto lo store tornerebbe sul
      // socio a sessione spenta — cioè scritture reali a suo nome, senza più
      // Layer A né Layer B ad arrestarle.
      SimulationController.stop();
      dispatchUserRefreshIfCurrent(target);

      expect(SimulationSession.isActive, isFalse);
      expect(store.state.user!.uid, admin.uid,
          reason:
              'lo store deve restare sull\'admin: un refresh aggiorna i dati '
              'di chi sei, non cambia chi sei');
    });

    test('un refresh in volo sull\'admin non sporca l\'avvio (race simmetrica)',
        () {
      // Direzione opposta: la HomePage dell'admin non viene smontata quando si
      // pusha UserDetailPage, da cui parte la simulazione. Il suo
      // `getUserData(admin)` che torna dopo lo start lascerebbe la barra accesa
      // con l'admin nello store — diagnosi silenziosamente sbagliata.
      inSimulazione();

      dispatchUserRefreshIfCurrent(admin);

      expect(store.state.user!.uid, target.uid);
      expect(SimulationSession.isActive, isTrue);
    });

    test('un refresh sulla stessa identità passa (non rompe il caso normale)',
        () {
      store.dispatch(SetUserAction(admin));
      final aggiornato =
          simUser(uid: 'admin-1', role: 'Admin', name: 'Anna Aggiornata');

      dispatchUserRefreshIfCurrent(aggiornato);

      expect(store.state.user!.name, 'Anna Aggiornata');
    });
  });
}
