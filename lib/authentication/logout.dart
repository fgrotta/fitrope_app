import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/services/onesignal_service.dart';

Future<void> signOut() async {
  // Prima di tutto: una sessione di simulazione lasciata viva dietro la
  // schermata di login bloccherebbe le chiamate OneSignal qui sotto (le loro
  // guardie lanciano) e resterebbe attiva al login successivo.
  //
  // E si ripristina l'ADMIN nello store PRIMA di qualunque await: se una delle
  // chiamate sotto lanciasse (OneSignal sul build wasm lo fa), ci troveremmo
  // con sessione spenta (guardie disarmate), `FirebaseAuth.currentUser` = admin
  // e `store.state.user` = socio ancora sullo schermo — scritture vere a nome
  // suo. Oggi ogni chiamante è già bloccato dal Layer A: questa è la rete.
  final realUser = SimulationSession.current.value?.realUser;
  SimulationSession.stop();
  if (realUser != null) {
    store.dispatch(SetUserAction(realUser));
  }
  // final email = FirebaseAuth.instance.currentUser?.email?.trim();
  // if (email != null && email.isNotEmpty) {
  //   await removeOneSignalEmail(email);
  //   await OneSignalService.removeEmail(email);
  // }
  await OneSignalService.setPushEnabled(false);
  await OneSignalService.logout();
  await FirebaseAuth.instance.signOut();
  debugPrint("User signed out");
}

void logoutRedirect(BuildContext context) {
  // Verifica se il context è ancora valido prima di navigare
  if (context.mounted) {
    Navigator.of(context).pushReplacementNamed(WELCOME_ROUTE);
  }
}
