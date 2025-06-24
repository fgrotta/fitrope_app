import 'package:firebase_auth/firebase_auth.dart';

Future<void> resetPassword(String email) async {
  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  } catch (e) {
    rethrow;
  }
} 