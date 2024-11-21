// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/registration.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: primaryColor,
      body: Padding(
        padding: const EdgeInsets.all(pagePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Email', style: TextStyle(color: ghostColor),),
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: ghostColor,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    hintStyle: TextStyle(color: ghostColor),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.white
                      )
                    ),
                  ),
                ),
                const SizedBox(height: 50,),
                const Text('Password', style: TextStyle(color: ghostColor),),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: ghostColor,
                  decoration: const InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(color: ghostColor),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.white
                      )
                    ),
                  ),
                  obscureText: true,
                ),
              ],
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width - pagePadding * 2,
              child: ElevatedButton(
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
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(secondaryColor),
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    )
                  )
                ), 
                child: const Text('Registrati', style: TextStyle(color: Colors.white),),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
