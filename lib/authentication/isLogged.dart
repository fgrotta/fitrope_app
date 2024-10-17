import 'package:firebase_auth/firebase_auth.dart';

bool isLogged() {
  User? user = FirebaseAuth.instance.currentUser;
  return user != null;
}