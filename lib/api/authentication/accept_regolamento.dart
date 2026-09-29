import "package:flutter/foundation.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/state/simulation_session.dart';

/// Salva l'accettazione del regolamento per l'utente specificato.
/// Scrive il campo `regolamentoAccettatoIl` con il timestamp corrente.
///
/// SELF-ONLY (PR6): le firestore.rules consentono `regolamentoAccettatoIl` solo
/// al proprietario del doc (è una marca probatoria, esclusa anche dall'update
/// Admin). Tutti i call site passano l'utente loggato — CalendarPage/HomePage
/// usano `store.state.user`, UserDetailPage mostra il bottone solo nel ramo
/// `store.state.user?.uid == widget.user.uid`. Chiamarla per conto di un altro
/// utente verrebbe rifiutata dal server (permission-denied).
///
/// WRITE-ONCE: le rules accettano la marca una sola volta e solo come
/// serverTimestamp. Una seconda chiamata (stato locale stantio) è rifiutata:
/// `RegolamentoHelper` la tratta rileggendo il documento.
Future<void> acceptRegolamento(
  String uid, {
  FirebaseFirestore? firestore,
}) async {
  SimulationSession.assertNotSimulating('acceptRegolamento');
  try {
    await (firestore ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .update({
      'regolamentoAccettatoIl': FieldValue.serverTimestamp(),
    });
    invalidateAllUserCaches();
  } catch (e) {
    debugPrint('Error saving regolamento acceptance: $e');
    rethrow;
  }
}
