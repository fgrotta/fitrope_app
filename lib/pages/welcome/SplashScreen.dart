import 'package:flutter/material.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/authentication/isLogged.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
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
    return const Scaffold(
      backgroundColor: Colors.white, // O il colore che preferisci
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // La tua immagine di caricamento
            const Image(
              image: AssetImage('assets/new_logo.png'),
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 30),
            // Indicatore di caricamento opzionale
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ],
        ),
      ),
    );
  }
}
