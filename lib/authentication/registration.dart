// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

Future<void> registerWithEmailPassword(String email, String password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    String uid = userCredential.user!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'name': 'Marco',
      'lastName': 'Della Rosa',
      'courses': [],
      'tipologiaIscrizione': 'PACCHETTO_ENTRATE',
      'entrateDisponibili': 74,
      'inizioIscrizione': FieldValue.serverTimestamp(),
      'fineIscrizione': FieldValue.serverTimestamp()
    });

    Map<String, dynamic>? userData = await getUserData(uid);
    print(userData);

    print("User registered: ${userCredential.user!.email}");
  } 
  on FirebaseAuthException catch (e) {
    if (e.code == 'weak-password') {
      print('The password provided is too weak.');
    } 
    else if (e.code == 'email-already-in-use') {
      print('The account already exists for that email.');
    } 
    else {
      print(e.message);
    }
  } 
  catch (e) {
    print(e);
  }
}