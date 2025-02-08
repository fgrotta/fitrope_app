import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

bool isLogged() {
  User? user = FirebaseAuth.instance.currentUser;
  return user != null && user.emailVerified;
}

void loggedRedirect(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Navigator.of(context).pushReplacementNamed(PROTECTED_ROUTE);
  });
}