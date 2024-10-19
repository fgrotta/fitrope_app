// ignore_for_file: avoid_print
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';

Future<Map<String, dynamic>?> signInWithEmailPassword(String email, String password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    print("User signed in: ${userCredential.user!.email}");

    if(userCredential.user != null) {
      String uid = userCredential.user!.uid;
      Map<String, dynamic>? userData = await getUserData(uid);
      return userData;
    }
  } 
  on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      print('No user found for that email.');
    } 
    else if (e.code == 'wrong-password') {
      print('Wrong password provided.');
    } 
    else {
      print(e.message);
    }
  } 
  catch (e) {
    print(e);
  }

  return null;
}
