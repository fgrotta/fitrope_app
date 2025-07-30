import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

Future<void> signOut() async {
  await FirebaseAuth.instance.signOut();
  print("User signed out");
}

void logoutRedirect(BuildContext context) {
  // Verifica se il context è ancora valido prima di navigare
  if (context.mounted) {
    Navigator.of(context).pushReplacementNamed(WELCOME_ROUTE);
  }
}
