import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/authentication/is_logged.dart';
// Stesso chunk deferred dell'area protetta usato dal router: pre-caricarlo qui
// (durante lo splash) evita il loader alla navigazione post-login. L'import è
// usato solo per `loadLibrary()` (nessun simbolo referenziato) → l'analyzer lo
// vede come "unused", ma è intenzionale.
// ignore: unused_import
import 'package:fitrope_app/pages/protected/protected.dart'
    deferred as protected;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Avvia il download del chunk dell'area protetta in parallelo allo splash
    // (fire-and-forget): se l'utente è loggato, alla navigazione sarà già pronto.
    unawaited(protected.loadLibrary());
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    // Simula un tempo di caricamento minimo
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      if (isLogged()) {
        Navigator.pushReplacementNamed(context, PROTECTED_ROUTE);
      } else {
        Navigator.pushReplacementNamed(context, WELCOME_ROUTE);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              isDesktop(context) ? MediaQuery.of(context).size.width * 0.25 : 0,
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image(
                image: AssetImage('assets/new_logo.png'),
                width: 200,
                height: 200,
              ),
              SizedBox(height: 30),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
