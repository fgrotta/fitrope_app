import 'package:fitrope_app/utils/simulation_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

void main() {
  final admin = simUser(uid: 'admin-1', role: 'Admin');
  final altroAdmin = simUser(uid: 'admin-2', role: 'Admin');
  final trainer = simUser(uid: 'trainer-1', role: 'Trainer');
  final utente = simUser(uid: 'user-1', role: 'User');

  bool can({
    dynamic actor,
    dynamic target,
    bool isMobileLayout = false,
    bool alreadySimulating = false,
  }) =>
      canSimulateUser(
        actor: actor,
        target: target,
        isMobileLayout: isMobileLayout,
        alreadySimulating: alreadySimulating,
      );

  group('canSimulateUser', () {
    test('Admin → User su tablet/desktop: consentito', () {
      expect(can(actor: admin, target: utente), isTrue);
    });

    test('actor null (utente non ancora caricato): negato', () {
      expect(can(actor: null, target: utente), isFalse);
    });

    test('un Trainer non può simulare', () {
      expect(can(actor: trainer, target: utente), isFalse);
    });

    test('un User non può simulare', () {
      expect(can(actor: utente, target: simUser(uid: 'user-2', role: 'User')),
          isFalse);
    });

    test('non si simula un altro Admin', () {
      expect(can(actor: admin, target: altroAdmin), isFalse);
    });

    test('non si simula un Trainer', () {
      expect(can(actor: admin, target: trainer), isFalse);
    });

    test('non si simula se stessi', () {
      expect(can(actor: admin, target: admin), isFalse);
    });

    test('su layout mobile: negato', () {
      expect(can(actor: admin, target: utente, isMobileLayout: true), isFalse);
    });

    test('già in simulazione: niente annidamento', () {
      expect(
          can(actor: admin, target: utente, alreadySimulating: true), isFalse);
    });
  });
}
