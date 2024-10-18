// ignore_for_file: avoid_print
import 'package:firebase_auth/firebase_auth.dart';

Future<void> signInWithEmailPassword(String email, String password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    print("User signed in: ${userCredential.user!.email}");
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
}


// Future<void> getUserData(String uid) async {
//   DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

//   if (userDoc.exists) {
//     Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
//     print('Username: ${userData['username']}');
//     print('Email: ${userData['email']}');
//     // Access other fields as needed
//   } else {
//     print('User document does not exist');
//   }
// }
