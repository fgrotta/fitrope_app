import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

Future<void> toggleUserStatus(String uid, bool isActive) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({
      'isActive': isActive,
    });

    invalidateAllUserCaches(); // Invalida tutte le cache degli utenti dopo l'aggiornamento
    print('User status updated successfully: $uid - isActive: $isActive');
  } catch (e) {
    print('Error updating user status: $e');
    throw e;
  }
} 