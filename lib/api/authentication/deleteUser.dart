import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

Future<void> deleteUser(String uid) async {
  try {
    // Elimina l'utente da Firestore
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    
    // Elimina l'utente da Firebase Auth (richiede autenticazione admin)
    // Nota: Questa operazione richiede privilegi di amministratore
    // await FirebaseAuth.instance.deleteUser(uid);
    
    // Invalida tutte le cache degli utenti dopo l'eliminazione
    invalidateAllUserCaches();
    
    debugPrint('User deleted successfully: $uid');
  } catch (e) {
    debugPrint('Error deleting user: $e');
    rethrow;
  }
} 