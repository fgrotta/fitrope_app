// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

class SignUpResponse {
  final FitropeUser? user;
  final String? error;

  SignUpResponse({
    this.user,
    this.error,
  });
}

Future<SignUpResponse> registerWithEmailPassword(String email, String password, String name, String lastName, {String? numeroTelefono}) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    String uid = userCredential.user!.uid;

    // Scadenza prova: 30 giorni, normalizzata a 23:59 (coerente col modello e
    // con updateUser, così i futuri edit non generano diff spuri sulla data).
    final DateTime d = DateTime.now().add(const Duration(days: 30));
    final DateTime fineIscrizione = DateTime(d.year, d.month, d.day, 23, 59);

    // Shape canonica COMPLETA (mirror della whitelist `create` self in
    // firestore.rules): niente campi server-owned, profilo di prova standard.
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'name': name,
      'lastName': lastName,
      'courses': [],
      'tipologiaIscrizione': 'ABBONAMENTO_PROVA', // abbonamento di prova
      'entrateDisponibili': 1, // 1 ingresso gratuito
      'entrateSettimanali': 0,
      'fineIscrizione': Timestamp.fromDate(fineIscrizione),
      'role': 'User',
      'numeroTelefono': numeroTelefono,
      'isActive': true,
      'isAnonymous': false,
      // Tag base: la firestore.rule create-self impone == ['Open']; teniamo il
      // valore agganciato alla costante per non duplicare la magic string.
      'tipologiaCorsoTags': CourseTags.defaultUserTags,
      'emailNotificationsEnabled': true,
      'pushNotificationsEnabled': true,
    });

    // Invalida tutte le cache degli utenti dopo la registrazione
    invalidateAllUserCaches();

    await userCredential.user!.sendEmailVerification();
    print("Email di verifica inviata a $email");

    Map<String, dynamic>? userData = await getUserData(uid);

    if (userData != null) {
      return SignUpResponse(
        user: FitropeUser.fromJson(userData),
      );
    }

    print("User registered: ${userCredential.user!.email}");
  } 
  on FirebaseAuthException catch (e) {
    if (e.code == 'weak-password') {
      return SignUpResponse(
        error: 'The password is too weak'
      );
    } 
    else if (e.code == 'email-already-in-use') {
      return SignUpResponse(
        error: 'The account already exists for that email.'
      );
    } 
    else {
      return SignUpResponse(
        error: e.message
      );
    }
  } 
  catch (e) {
    print(e);
  }
  
  return SignUpResponse(
    error: 'Error'
  );
}
