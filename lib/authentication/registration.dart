// ignore_for_file: avoid_print
import 'package:firebase_auth/firebase_auth.dart';

Future<void> registerWithEmailPassword(String email, String password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

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