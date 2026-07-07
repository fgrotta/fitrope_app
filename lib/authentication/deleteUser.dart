import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> deleteUser() async {
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