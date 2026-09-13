import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// L'invariante da cui dipende TUTTA la fedeltà visiva: in simulazione
/// `store.state.user` È l'utente simulato. È da qui che arrivano gratis
/// `getCourseState`, la sparizione delle tab admin e i ~45 confronti
/// `role == 'Admin'` sparsi nel codice.
///
/// Qui si testa la coppia sessione+store senza il remount (non unit-testabile:
/// richiede route table e deferred loading — copertura manuale sull'emulatore).
void main() {
  final admin = simUser(uid: 'admin-1', role: 'Admin', name: 'Anna');
  final target = simUser(uid: 'user-1', role: 'User', name: 'Mario');

  setUp(() => store.dispatch(SetUserAction(admin)));

  tearDown(() {
    SimulationSession.stop();
    store.dispatch(SetUserAction(null));
  });

  test('dopo start lo store espone l\'utente simulato', () {
    SimulationSession.start(admin: admin, target: target);
    store.dispatch(SetUserAction(target));

    expect(store.state.user!.uid, target.uid);
    expect(store.state.user!.role, 'User');
    // L'identità reale resta recuperabile: serve a uscire e alla barra.
    expect(SimulationSession.current.value!.realUser.uid, admin.uid);
  });

  test('dopo stop si torna all\'admin, dallo snapshot catturato allo start',
      () {
    SimulationSession.start(admin: admin, target: target);
    store.dispatch(SetUserAction(target));

    final ripristino = SimulationSession.current.value!.realUser;
    SimulationSession.stop();
    store.dispatch(SetUserAction(ripristino));

    expect(store.state.user!.uid, admin.uid);
    expect(store.state.user!.role, 'Admin');
    expect(SimulationSession.isActive, isFalse);
  });
}
