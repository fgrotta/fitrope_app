// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/registration.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
          const Text('Registration'),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          ElevatedButton(
            onPressed: () {
              registerWithEmailPassword(
                _emailController.text,
                _passwordController.text,
              ).then((FitropeUser? user) {
                if(user != null) {
                  store.dispatch(SetUserAction(user));
                  Navigator.pushNamed(context, PROTECTED_ROUTE);
                }
              });
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
}
