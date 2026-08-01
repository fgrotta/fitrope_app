import "package:flutter/foundation.dart";
import 'package:firebase_auth/firebase_auth.dart';

Future<void> resendVerificationEmail() async {
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
