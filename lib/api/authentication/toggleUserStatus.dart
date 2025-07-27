import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

Future<void> toggleUserStatus(String uid, bool isActive) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({
      'isActive': isActive,
    });

    invalidateUsersCache(); // Invalida la cache dopo l'aggiornamento
    print('User status updated successfully: $uid - isActive: $isActive');
  } catch (e) {
    print('Error updating user status: $e');
    throw e;
  }
} 