import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

bool isLogged() {
  User? user = FirebaseAuth.instance.currentUser;
  return user != null && user.emailVerified;
}

void loggedRedirect(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Solo se la pagina è in cima. Le route iniziali (`/splash`, oppure
    // `/protected` al reload) fanno costruire la Welcome SOTTO: da lì
    // `pushReplacementNamed` sostituirebbe la route in cima, cioè un
    // `Protected` già montato, con un secondo (doppio `getUserData`).
    if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(PROTECTED_ROUTE);
  });
}
