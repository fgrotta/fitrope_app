import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    if(isLogged()){
      loggedRedirect(context);
    }
  }

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