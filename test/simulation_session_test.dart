import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

void main() {
  // Il singleton è globale: ogni test riparte da sessione spenta.
  tearDown(SimulationSession.stop);

  final admin = simUser(uid: 'admin-1', role: 'Admin');
  final target = simUser(uid: 'user-1', role: 'User');

  group('SimulationSession', () {
    test('parte inattiva', () {
      expect(SimulationSession.isActive, isFalse);
      expect(SimulationSession.current.value, isNull);
    });

    test('start popola realUser e simulatedUser', () {
      SimulationSession.start(admin: admin, target: target);

      expect(SimulationSession.isActive, isTrue);
      expect(SimulationSession.current.value!.realUser.uid, 'admin-1');
      expect(SimulationSession.current.value!.simulatedUser.uid, 'user-1');
    });

    test('il notifier notifica sia in entrata sia in uscita', () {
      var notifiche = 0;
      void listener() => notifiche++;
      SimulationSession.current.addListener(listener);
      addTearDown(() => SimulationSession.current.removeListener(listener));

      SimulationSession.start(admin: admin, target: target);
      expect(notifiche, 1);

      SimulationSession.stop();
      expect(notifiche, 2);
    });

    test('stop a sessione inattiva è un no-op', () {
      var notifiche = 0;
      void listener() => notifiche++;
      SimulationSession.current.addListener(listener);
      addTearDown(() => SimulationSession.current.removeListener(listener));

      SimulationSession.stop();

      expect(notifiche, 0);
      expect(SimulationSession.isActive, isFalse);
    });

    test('start annidato lancia: l\'identità reale non va falsificata', () {
      SimulationSession.start(admin: admin, target: target);

      expect(
        () => SimulationSession.start(
            admin: admin, target: simUser(uid: 'user-2', role: 'User')),
        throwsStateError,
      );
      // La sessione originale resta intatta.
      expect(SimulationSession.current.value!.simulatedUser.uid, 'user-1');
    });
  });

  group('assertNotSimulating', () {
    test('non lancia a simulazione spenta', () {
      expect(() => SimulationSession.assertNotSimulating('updateUser'),
          returnsNormally);
    });

    test('lancia SimulationBlockedException in simulazione', () {
      SimulationSession.start(admin: admin, target: target);

      expect(
        () => SimulationSession.assertNotSimulating('updateUser'),
        throwsA(isA<SimulationBlockedException>()),
      );
    });

    test('toString() è la sola frase italiana, senza prefisso Exception', () {
      const e = SimulationBlockedException('updateUser');

      expect(e.toString(), kSimulationBlockedMessage);
      expect(e.toString(), isNot(contains('Exception')));
    });

    test('signOut non disarma la sessione prima di bloccare il logout',
        () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        signOut(),
        throwsA(isA<SimulationBlockedException>()),
      );

      expect(SimulationSession.isActive, isTrue);
      expect(SimulationSession.current.value!.simulatedUser.uid, target.uid);
    });
  });
}
