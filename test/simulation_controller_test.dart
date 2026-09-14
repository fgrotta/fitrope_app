import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/utils/refresh_current_user.dart';
import 'package:fitrope_app/utils/simulation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Copre `SimulationController` **eseguendolo**, non ri-implementandone la
/// sequenza: è il pezzo che tiene insieme sessione, store e remount, ed è lo
/// stesso file in cui un bug (Navigator.of dalla barra) è già arrivato fino al
/// QA manuale.
///
/// `stop()` è testabile così com'è: non prende un `BuildContext`, e `_remount()`
/// senza `appNavigatorKey` montata si limita a loggare e uscire — tutto il resto
/// del metodo gira. `start(BuildContext)` richiede una route table e il deferred
/// loading, quindi resta coperto dal QA manuale.
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
