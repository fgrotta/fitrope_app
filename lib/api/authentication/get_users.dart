import "package:flutter/foundation.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';

// Cache per gli utenti
List<FitropeUser>? _cachedUsers;
DateTime? _lastCacheTime;
const Duration _cacheDuration = Duration(minutes: 5);

// Cache per i trainer
List<FitropeUser>? _cachedTrainers;
DateTime? _lastTrainersCacheTime;
const Duration _trainersCacheDuration = Duration(minutes: 5);

Future<FitropeUser?> getUser(String uid, {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final usersCollection = db.collection('users');
  final snapshot = await usersCollection.doc(uid).get();
  final data = snapshot.data();
  if (data == null) {
    return null;
  }
  // 'uid' dall'id del documento: non tutti i documenti users lo hanno salvato
  // come campo (es. creati server-side).
  return FitropeUser.fromJson({...data, 'uid': snapshot.id});
}

Future<List<FitropeUser>> getUsers({FirebaseFirestore? firestore}) async {
  // Controlla se la cache è ancora valida
  if (_cachedUsers != null && _lastCacheTime != null) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTime!);
    if (timeSinceLastCache < _cacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedUsers!;
    }
  }

  try {
    final db = firestore ?? FirebaseFirestore.instance;
    final usersCollection = db.collection('users');
    final snapshot = await usersCollection.get();

    // Deserializzazione tramite FitropeUser.fromJson: una mappatura manuale qui
    // si dimenticherebbe (come e successo con activeSubscriptions/waitlistCourses/
    // preferenze notifiche) i campi aggiunti al modello. 'uid' e messo DOPO lo
    // spread per far vincere doc.id su un eventuale uid stantio nel documento.
    final usersList = snapshot.docs
        .map((doc) {
          try {
            return FitropeUser.fromJson({...doc.data(), 'uid': doc.id});
          } catch (e) {
            // getUsers carica TUTTI gli utenti: un documento malformato non deve
            // far fallire l'intera lista admin, si salta solo quello.
            debugPrint('Utente ${doc.id} non deserializzabile, saltato: $e');
            return null;
          }
        })
        .whereType<FitropeUser>()
        .toList();

    // Aggiorna la cache
    _cachedUsers = usersList;
    _lastCacheTime = DateTime.now();

    return usersList;
  } catch (e) {
    debugPrint('Error loading users: $e');
    rethrow;
  }
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersCache() {
  _cachedUsers = null;
  _lastCacheTime = null;
  _cachedTrainers = null;
  _lastTrainersCacheTime = null;
}

// Funzione per ottenere solo i trainer
Future<List<FitropeUser>> getTrainers({FirebaseFirestore? firestore}) async {
  // Controlla se la cache è ancora valida
  if (_cachedTrainers != null && _lastTrainersCacheTime != null) {
    final timeSinceLastCache =
        DateTime.now().difference(_lastTrainersCacheTime!);
    if (timeSinceLastCache < _trainersCacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedTrainers!;
    }
  }

  try {
    final usersList = await getUsers(firestore: firestore);
    final trainersList = usersList
        .where((user) => user.role == 'Trainer' && user.isActive)
        .toList();

    // Aggiorna la cache dei trainer
    _cachedTrainers = trainersList;
    _lastTrainersCacheTime = DateTime.now();

    return trainersList;
  } catch (e) {
    debugPrint('Error loading trainers: $e');
    rethrow;
  }
}
