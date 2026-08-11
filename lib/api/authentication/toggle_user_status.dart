import "package:flutter/foundation.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

Future<void> toggleUserStatus(String uid, bool isActive) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isActive': isActive,
    });

    invalidateAllUserCaches(); // Invalida tutte le cache degli utenti dopo l'aggiornamento
    debugPrint('User status updated successfully: $uid - isActive: $isActive');
  } catch (e) {
    debugPrint('Error updating user status: $e');
    rethrow;
  }
}
