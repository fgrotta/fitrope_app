import 'package:firebase_auth/firebase_auth.dart';

Future<void> deleteUser() async {
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await user.delete();
      print("Utente eliminato con successo.");
    } else {
      print("Nessun utente autenticato.");
    }
  } catch (e) {
    print("Errore durante l'eliminazione dell'utente: $e");
  }
}