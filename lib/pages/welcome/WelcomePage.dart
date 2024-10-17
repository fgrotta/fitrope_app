import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Welcome Page'),
          ElevatedButton(onPressed: () { Navigator.pushNamed(context, LOGIN_ROUTE); }, child: const Text('Entra')),
          ElevatedButton(onPressed: () { Navigator.pushNamed(context, REGISTRATION_ROUTE); }, child: const Text('Registrati')),
        ],
      ),
    );
  }
}