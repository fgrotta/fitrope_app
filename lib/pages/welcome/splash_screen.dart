import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/authentication/is_logged.dart';
// Stesso chunk deferred dell'area protetta usato dal router: pre-caricarlo qui
// (durante lo splash) evita il loader alla navigazione. Serve solo a chi è già
// loggato. L'import è usato solo per `loadLibrary()` (nessun simbolo
// referenziato) → l'analyzer lo vede come "unused", ma è intenzionale.
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
    // Nessuna attesa fissa: si naviga appena lo stato di autenticazione è noto.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _navigateToNextScreen());
  }

  Future<void> _navigateToNextScreen() async {
    // Rete di sicurezza sul web: `Firebase.initializeApp` attende già il
    // ripristino della sessione salvata, ma il primo evento di
    // `authStateChanges` è la garanzia esplicita che `currentUser` sia
    // definitivo prima di scegliere la route.
    await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (isLogged()) {
      // Il logo resta a schermo finché il chunk dell'area protetta non è
      // pronto (sotto --wasm è già nel modulo unico e ritorna subito). Se il
      // download fallisce si naviga comunque: `DeferredPage` mostra
      // il suo stato di errore invece di uno splash bloccato.
      try {
        await protected.loadLibrary();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, PROTECTED_ROUTE);
    } else {
      Navigator.pushReplacementNamed(context, WELCOME_ROUTE);
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
