import 'package:firebase_auth/firebase_auth.dart';

Future<void> resendVerificationEmail() async {
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      print("Email di verifica inviata con successo.");
    } else {
      print("L'utente è già verificato o non è autenticato.");
    }
  } catch (e) {
    print("Errore durante l'invio dell'email di verifica: $e");
  }
}
