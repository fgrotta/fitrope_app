import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

Future<List<FitropeUser>> getUsers() async {
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
      );
    }).toList();

    return usersList;
  } catch (e) {
    print('Error loading users: $e');
    throw e;
  }
} 