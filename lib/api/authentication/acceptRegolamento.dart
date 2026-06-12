import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

/// Salva l'accettazione del regolamento per l'utente specificato.
/// Scrive il campo `regolamentoAccettatoIl` con il timestamp corrente.
///
/// SELF-ONLY (PR6): le firestore.rules consentono `regolamentoAccettatoIl` solo
/// al proprietario del doc (è una marca probatoria, esclusa anche dall'update
/// Admin). Tutti i call site passano l'utente loggato — CalendarPage/HomePage
/// usano `store.state.user`, UserDetailPage mostra il bottone solo nel ramo
/// `store.state.user?.uid == widget.user.uid`. Chiamarla per conto di un altro
/// utente verrebbe rifiutata dal server (permission-denied).
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
