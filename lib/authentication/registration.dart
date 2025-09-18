// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

class SignUpResponse {
  final FitropeUser? user;
  final String? error;

  SignUpResponse({
    this.user,
    this.error,
  });
}

Future<SignUpResponse> registerWithEmailPassword(String email, String password, String name, String lastName) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    String uid = userCredential.user!.uid;

    // Calcola la data di scadenza (45 giorni da oggi)
    DateTime fineIscrizione = DateTime.now().add(const Duration(days: 30));

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'name': name,
      'lastName': lastName,
      'courses': [],
      'tipologiaIscrizione': 'ABBONAMENTO_PROVA', // Assegna abbonamento di prova
      'entrateDisponibili': 1, // 1 ingresso gratuito
      'entrateSettimanali': 0,
      'fineIscrizione': Timestamp.fromDate(fineIscrizione), // 45 giorni da oggi
      'role': 'User',
    });

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
