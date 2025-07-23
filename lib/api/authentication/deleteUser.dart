import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> deleteUser(String uid) async {
  try {
    // Elimina l'utente da Firestore
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    
    // Elimina l'utente da Firebase Auth (richiede autenticazione admin)
    // Nota: Questa operazione richiede privilegi di amministratore
    // await FirebaseAuth.instance.deleteUser(uid);
    
    print('User deleted successfully: $uid');
  } catch (e) {
    print('Error deleting user: $e');
    throw e;
  }
} 