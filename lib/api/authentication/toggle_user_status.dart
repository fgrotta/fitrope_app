import "package:flutter/foundation.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/state/simulation_session.dart';

Future<void> toggleUserStatus(String uid, bool isActive) async {
  SimulationSession.assertNotSimulating('toggleUserStatus');
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
