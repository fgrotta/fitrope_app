import 'package:fitrope_app/authentication/login.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/authentication/registration.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase Auth Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                registerWithEmailPassword(
                  _emailController.text,
                  _passwordController.text,
                );
              },
              child: const Text('Register'),
            ),
            ElevatedButton(
              onPressed: () {
                signInWithEmailPassword(
                  _emailController.text,
                  _passwordController.text,
                );
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
        ),
      ),
    );
  }
}
