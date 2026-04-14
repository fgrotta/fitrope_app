import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

/// Salva l'accettazione del regolamento per l'utente specificato.
/// Scrive il campo `regolamentoAccettatoIl` con il timestamp corrente.
Future<void> acceptRegolamento(String uid) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'regolamentoAccettatoIl': FieldValue.serverTimestamp(),
    });
    invalidateAllUserCaches();
  } catch (e) {
    print('Error saving regolamento acceptance: $e');
    rethrow;
  }
}
