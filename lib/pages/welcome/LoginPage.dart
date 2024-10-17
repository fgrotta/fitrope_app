// ignore_for_file: use_build_context_synchronously
import 'package:fitrope_app/authentication/login.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  void onLogin() async {
    await signInWithEmailPassword(
      _emailController.text,
      _passwordController.text,
    );

    Navigator.pushNamed(context, PROTECTED_ROUTE);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Login'),
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
              onLogin();
            },
            child: const Text('Login'),
          ),
          ElevatedButton(
            onPressed: () {
              signOut();
            },
            child: const Text('Logout'),
          ),
        ],
      )
    );
  }
}