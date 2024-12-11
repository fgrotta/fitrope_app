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
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  String? emailError;
  String? passwordError;
  String? confirmPasswordError;
  String? nameError;
  String? lastNameError;

  @override
  void initState() {
    super.initState();
    if(isLogged()){
      loggedRedirect(context);
    }
  }

  void validateEmail() {
    if(_emailController.text.isEmpty) {
      emailError = "L'email non è valida";
    }
    else {
      emailError = null;
    }
  }

  void validatePassword() {
    if(_passwordController.text.length < 6) {
      passwordError = "La password deve essere lunga almeno 6 caratteri";
    }
    else if(_passwordController.text != _confirmPasswordController.text) {
      passwordError = "Le password devono essere uguali";
      confirmPasswordError = "Le password devono essere uguali";
    }
    else {
      passwordError = null;
      confirmPasswordError = null;
    }
  }

  void validateName() {
    if(_nameController.text.length < 2) {
      nameError = "Il nome non è valido";
    }
    else {
      nameError = null;
    }
  }

  void validateLastName() {
    if(_lastNameController.text.length < 2) {
      lastNameError = "Il cognome non è valido";
    }
    else {
      lastNameError = null;
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
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Email', style: TextStyle(color: ghostColor),),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _emailController, hintText: 'Inserisci la tua email', onTapOutside: (_) => setState(() { validateEmail(); }),),
                  const SizedBox(height: 5,),
                  Text(emailError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Password', style: TextStyle(color: ghostColor),),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _passwordController, hintText: 'Inserisci la password', obscureText: true, onTapOutside: (_) => setState(() { validatePassword(); }),),
                  const SizedBox(height: 5,),
                  Text(passwordError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Conferma password', style: TextStyle(color: ghostColor),),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _confirmPasswordController, hintText: 'Conferma la password', obscureText: true, onTapOutside: (_) => setState(() { validatePassword(); }),),
                  const SizedBox(height: 5,),
                  Text(confirmPasswordError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Nome', style: TextStyle(color: ghostColor),),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _nameController, hintText: 'Inserisci il tuo nome', onTapOutside: (_) => setState(() { validateName(); }),),
                  const SizedBox(height: 5,),
                  Text(nameError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Cognome', style: TextStyle(color: ghostColor),),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _lastNameController, hintText: 'Inserisci il tuo cognome', onTapOutside: (_) => setState(() { validateLastName(); }),),
                  const SizedBox(height: 5,),
                  Text(lastNameError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                ],
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width - pagePadding * 2,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      validateName();
                      validateLastName();
                      validateEmail();
                      validatePassword();
                    });

                    if(
                      nameError != null ||
                      lastNameError != null ||
                      emailError != null || 
                      passwordError != null || 
                      confirmPasswordError != null
                    ) {
                      return;
                    }


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
      ),
    );
  }
}
