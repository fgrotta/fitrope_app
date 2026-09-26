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

// Letture in corso e generazione della cache (vedi invalidateUsersCache).
Future<List<FitropeUser>>? _usersInFlight;
Future<List<FitropeUser>>? _trainersInFlight;
int _usersGeneration = 0;
int _trainersGeneration = 0;

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

  // De-dup in volo: chi chiama mentre una lettura è già partita riceve lo
  // stesso Future invece di rileggere l'intera collection.
  final inFlight = _usersInFlight;
  if (inFlight != null) return inFlight;

  final generation = _usersGeneration;
  final future =
      _fetchUsers(firestore ?? FirebaseFirestore.instance).then((usersList) {
    // Un'invalidazione arrivata durante il volo vince: la lista letta prima
    // della mutazione non deve finire in cache.
    if (generation == _usersGeneration) {
      _cachedUsers = usersList;
      _lastCacheTime = DateTime.now();
    }
    return usersList;
  });
  _usersInFlight = future;
  try {
    return await future;
  } finally {
    if (identical(_usersInFlight, future)) _usersInFlight = null;
  }
}

Future<List<FitropeUser>> _fetchUsers(FirebaseFirestore db) async {
  try {
    final snapshot = await db.collection('users').get();
    return _deserializeUsers(snapshot.docs);
  } catch (e) {
    debugPrint('Error loading users: $e');
    rethrow;
  }
}

// Deserializzazione tramite FitropeUser.fromJson: una mappatura manuale qui
// si dimenticherebbe (come e successo con activeSubscriptions/waitlistCourses/
// preferenze notifiche) i campi aggiunti al modello. 'uid' e messo DOPO lo
// spread per far vincere doc.id su un eventuale uid stantio nel documento.
List<FitropeUser> _deserializeUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  return docs
      .map((doc) {
        try {
          return FitropeUser.fromJson({...doc.data(), 'uid': doc.id});
        } catch (e) {
          // Un documento malformato non deve far fallire l'intera lista, si
          // salta solo quello.
          debugPrint('Utente ${doc.id} non deserializzabile, saltato: $e');
          return null;
        }
      })
      .whereType<FitropeUser>()
      .toList();
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateUsersCache() {
  _cachedUsers = null;
  _lastCacheTime = null;
  _cachedTrainers = null;
  _lastTrainersCacheTime = null;
  // Le letture ancora in volo non scriveranno più la cache; le prossime
  // chiamate ripartono dal server invece di agganciarsi a quelle.
  _usersGeneration++;
  _trainersGeneration++;
  _usersInFlight = null;
  _trainersInFlight = null;
}

/// Solo i trainer attivi, con una query dedicata: i soci ne hanno bisogno
/// (nome del trainer sulle card) ma non devono scaricare l'intera collection
/// `users`. Le rules consentono la `list` a ogni utente autenticato.
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

  final inFlight = _trainersInFlight;
  if (inFlight != null) return inFlight;

  final generation = _trainersGeneration;
  final future = _fetchTrainers(firestore ?? FirebaseFirestore.instance)
      .then((trainersList) {
    if (generation == _trainersGeneration) {
      _cachedTrainers = trainersList;
      _lastTrainersCacheTime = DateTime.now();
    }
    return trainersList;
  });
  _trainersInFlight = future;
  try {
    return await future;
  } finally {
    if (identical(_trainersInFlight, future)) _trainersInFlight = null;
  }
}

Future<List<FitropeUser>> _fetchTrainers(FirebaseFirestore db) async {
  try {
    // Un solo filtro Firestore (nessun indice composito): `isActive` si
    // filtra in memoria, i trainer sono pochi.
    final snapshot =
        await db.collection('users').where('role', isEqualTo: 'Trainer').get();
    return _deserializeUsers(snapshot.docs)
        .where((user) => user.isActive)
        .toList();
  } catch (e) {
    debugPrint('Error loading trainers: $e');
    rethrow;
  }
}
