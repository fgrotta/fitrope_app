import "package:flutter/foundation.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/state/simulation_session.dart';

Future<void> deleteUser() async {
  // FUORI dal try: il catch qui sotto inghiotte tutto. E `currentUser` in
  // simulazione è l'ADMIN: questa cancellerebbe il suo account.
  SimulationSession.assertNotSimulating('deleteUser');
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await user.delete();
      debugPrint("Utente eliminato con successo.");
    } else {
      debugPrint("Nessun utente autenticato.");
    }
  } catch (e) {
    debugPrint("Errore durante l'eliminazione dell'utente: $e");
  }
}
