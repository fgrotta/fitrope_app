import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/services/notification_service.dart';
import 'package:fitrope_app/services/onesignal_service.dart';

Future<void> signOut() async {
  final email = FirebaseAuth.instance.currentUser?.email?.trim();
  if (email != null && email.isNotEmpty) {
    await removeOneSignalEmail(email);
    await OneSignalService.removeEmail(email);
  }
  await OneSignalService.logout();
  await FirebaseAuth.instance.signOut();
  print("User signed out");
}

void logoutRedirect(BuildContext context) {
  // Verifica se il context è ancora valido prima di navigare
  if (context.mounted) {
    Navigator.of(context).pushReplacementNamed(WELCOME_ROUTE);
  }
}
