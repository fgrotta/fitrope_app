import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/utils/course_tags.dart';

class CreateUserResponse {
  final FitropeUser? user;
  final String? error;

  CreateUserResponse({
    this.user,
    this.error,
  });
}

/// Crea un nuovo utente con validazione automatica
/// Solo Admin e Trainer possono utilizzare questa funzione
Future<CreateUserResponse> createUser({
  String? email,
  String? password,
  required String name,
  required String lastName,
  required String role,
  TipologiaIscrizione? tipologiaIscrizione,
  int? entrateDisponibili,
  int? entrateSettimanali,
  DateTime? fineIscrizione,
  bool isAnonymous = false,
  String? numeroTelefono,
  List<String>? tipologiaCorsoTags,
}) async {
  try {
    // Verifica che l'utente corrente abbia i permessi necessari
    CollectionReference postsRef = FirebaseFirestore.instance.collection('users');
    var newID = postsRef.doc().id;
    // Crea il documento utente in Firestore

    final userData = {
      'uid': newID,
      'email': email ?? '-', // Email vuota se non fornita
      'name': name,
      'lastName': lastName,
      'role': role,
      'courses': [],
      'tipologiaIscrizione': tipologiaIscrizione?.toString().split('.').last ?? 'ABBONAMENTO_PROVA',
      'entrateDisponibili': entrateDisponibili ?? 1,
      'entrateSettimanali': entrateSettimanali ?? 0,
      'fineIscrizione': null,
      'isActive': true, // L'utente viene creato come attivo
      'isAnonymous': isAnonymous,
      'createdAt': FieldValue.serverTimestamp(),
      'numeroTelefono': numeroTelefono,
      'tipologiaCorsoTags': tipologiaCorsoTags ?? CourseTags.defaultUserTags,
      'cancelledEnrollments': [],
    };

    await postsRef.doc(newID).set(userData);

    // Invalida tutte le cache degli utenti
    invalidateAllUserCaches();

    // Crea l'oggetto FitropeUser per la risposta
    final fitropeUser = FitropeUser(
      uid: newID,
      email: email ?? '',
      name: name,
      lastName: lastName,
      role: role,
      courses: [],
      tipologiaIscrizione: tipologiaIscrizione ?? TipologiaIscrizione.ABBONAMENTO_PROVA,
      entrateDisponibili: entrateDisponibili ?? 1,
      entrateSettimanali: entrateSettimanali ?? 0,
      fineIscrizione: null,
      isActive: true,
      isAnonymous: isAnonymous,
      createdAt: DateTime.now(),
      numeroTelefono: numeroTelefono,
      tipologiaCorsoTags: tipologiaCorsoTags ?? CourseTags.defaultUserTags,
    );

    print('User created successfully: ${email ?? 'no-email'} with role $role');
    return CreateUserResponse(user: fitropeUser);

  } on FirebaseAuthException catch (e) {
    String errorMessage;
    switch (e.code) {
      case 'weak-password':
        errorMessage = 'La password è troppo debole';
        break;
      case 'email-already-in-use':
        errorMessage = 'Esiste già un account con questa email';
        break;
      case 'invalid-email':
        errorMessage = 'L\'email non è valida';
        break;
      default:
        errorMessage = 'Errore durante la creazione dell\'utente: ${e.message}';
    }
    return CreateUserResponse(error: errorMessage);
  } catch (e) {
    print('Error creating user: $e');
    return CreateUserResponse(error: 'Errore durante la creazione dell\'utente');
  }
}
