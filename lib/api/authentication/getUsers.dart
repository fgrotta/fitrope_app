import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_tags.dart';

// Cache per gli utenti
List<FitropeUser>? _cachedUsers;
DateTime? _lastCacheTime;
const Duration _cacheDuration = Duration(minutes: 5);

// Cache per i trainer
List<FitropeUser>? _cachedTrainers;
DateTime? _lastTrainersCacheTime;
const Duration _trainersCacheDuration = Duration(minutes: 5);



Future<FitropeUser?> getUser(String uid) async {
  final usersCollection = FirebaseFirestore.instance.collection('users');
  final snapshot = await usersCollection.doc(uid).get();
  final data = snapshot.data();
  if(data == null) {
    return null;
  }
  return FitropeUser.fromJson(data);
}

Future<List<FitropeUser>> getUsers() async {
  // Controlla se la cache è ancora valida
  if (_cachedUsers != null && _lastCacheTime != null) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTime!);
    if (timeSinceLastCache < _cacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedUsers!;
    }
  }

  try {
    final usersCollection = FirebaseFirestore.instance.collection('users');
    final snapshot = await usersCollection.get();
    
    final usersList = snapshot.docs.map((doc) {
      final data = doc.data();
      return FitropeUser(
        uid: doc.id,
        email: data['email'] ?? '',
        name: data['name'] ?? '',
        lastName: data['lastName'] ?? '',
        role: data['role'] ?? 'User',
        courses: List<String>.from(data['courses'] ?? []),
        tipologiaIscrizione: data['tipologiaIscrizione'] != null 
            ? TipologiaIscrizione.values.where((e) => e.toString().split('.').last == data['tipologiaIscrizione']).firstOrNull
            : null,
        entrateDisponibili: data['entrateDisponibili'] as int?,
        entrateSettimanali: data['entrateSettimanali'] as int?,
        fineIscrizione: data['fineIscrizione'] as Timestamp?,
        createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
        isActive: data['isActive'] ?? true,
        isAnonymous: data['isAnonymous'] ?? false,
        certificatoScadenza: data['certificatoScadenza'] as Timestamp?,
        numeroTelefono: data['numeroTelefono'] as String?,
        tipologiaCorsoTags: (data['tipologiaCorsoTags'] as List<dynamic>?)
          ?.map((tag) => tag.toString())
          .toList() ?? CourseTags.defaultUserTags,
      );
    }).toList();

    // Aggiorna la cache
    _cachedUsers = usersList;
    _lastCacheTime = DateTime.now();

    return usersList;
  } catch (e) {
    print('Error loading users: $e');
    throw e;
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
Future<List<FitropeUser>> getTrainers() async {
  // Controlla se la cache è ancora valida
  if (_cachedTrainers != null && _lastTrainersCacheTime != null) {
    final timeSinceLastCache = DateTime.now().difference(_lastTrainersCacheTime!);
    if (timeSinceLastCache < _trainersCacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedTrainers!;
    }
  }

  try {
    final usersList = await getUsers();
    final trainersList = usersList.where((user) => user.role == 'Trainer' && user.isActive).toList();
    
    // Aggiorna la cache dei trainer
    _cachedTrainers = trainersList;
    _lastTrainersCacheTime = DateTime.now();

    return trainersList;
  } catch (e) {
    print('Error loading trainers: $e');
    throw e;
  }
}