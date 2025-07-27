import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

Future<void> updateUser({
  required String uid,
  required String name,
  required String lastName,
  required String role,
  TipologiaIscrizione? tipologiaIscrizione,
  int? entrateDisponibili,
  int? entrateSettimanali,
  DateTime? fineIscrizione,
}) async {
  try {
    final updateData = <String, dynamic>{
      'name': name,
      'lastName': lastName,
      'role': role,
      'tipologiaIscrizione': tipologiaIscrizione?.toString().split('.').last,
      'entrateDisponibili': entrateDisponibili,
      'entrateSettimanali': entrateSettimanali,
      'fineIscrizione': fineIscrizione != null ? Timestamp.fromDate(DateTime(fineIscrizione.year, fineIscrizione.month, fineIscrizione.day, 23, 59)) : null,
    };

    // Rimuovi i campi null per non sovrascriverli con null
    updateData.removeWhere((key, value) => value == null);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update(updateData);

    invalidateUsersCache(); // Invalida la cache dopo l'aggiornamento
    print('User updated successfully: $uid');
  } catch (e) {
    print('Error updating user: $e');
    throw e;
  }
} 