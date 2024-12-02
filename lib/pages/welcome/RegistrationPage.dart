// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/registration.dart';
import 'package:fitrope_app/components/custom_text_field.dart';
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

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
        title: const Text("Registrazione", style: TextStyle(color: Colors.white),),
      ),
      backgroundColor: primaryColor,
      body: Padding(
        padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Email', style: TextStyle(color: ghostColor),),
                const SizedBox(height: 10,),
                CustomTextField(controller: _emailController, hintText: 'Inserisci la tua email',),
                const SizedBox(height: 20,),
                const Text('Password', style: TextStyle(color: ghostColor),),
                const SizedBox(height: 10,),
                CustomTextField(controller: _passwordController, hintText: 'Inserisci la password', obscureText: true,),
                const SizedBox(height: 20,),
                const Text('Nome', style: TextStyle(color: ghostColor),),
                const SizedBox(height: 10,),
                CustomTextField(controller: _nameController, hintText: 'Inserisci il tuo nome'),
                const SizedBox(height: 20,),
                const Text('Cognome', style: TextStyle(color: ghostColor),),
                const SizedBox(height: 10,),
                CustomTextField(controller: _lastNameController, hintText: 'Inserisci il tuo cognome'),
              ],
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width - pagePadding * 2,
              child: ElevatedButton(
                onPressed: () {
                  registerWithEmailPassword(
                    _emailController.text,
                    _passwordController.text,
                    _nameController.text,
                    _lastNameController.text
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
