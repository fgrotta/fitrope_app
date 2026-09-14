import "package:flutter/foundation.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/state/simulation_session.dart';

Future<void> resendVerificationEmail() async {
  SimulationSession.assertNotSimulating('resendVerificationEmail');
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      debugPrint("Email di verifica inviata con successo.");
    } else {
      debugPrint("L'utente è già verificato o non è autenticato.");
    }
  } catch (e) {
    debugPrint("Errore durante l'invio dell'email di verifica: $e");
  }
}
