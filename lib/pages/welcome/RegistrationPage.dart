// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/registration.dart';
import 'package:fitrope_app/components/custom_text_field.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _numeroTelefonoController = TextEditingController();

  String? emailError;
  String? passwordError;
  String? confirmPasswordError;
  String? nameError;
  String? lastNameError;
  String? numeroTelefonoError;
  String? registrationError;
  String? privacyError;

  bool validatingEmail = false;
  bool privacyAccepted = false;

  @override
  void initState() {
    super.initState();
    if(isLogged()){
      loggedRedirect(context);
    }
  }

  void validateEmail() {
    if(_emailController.text.trim().isEmpty) {
      emailError = "L'email non è valida";
    }
    else {
      emailError = null;
    }
  }

  void validatePassword() {
    if(_passwordController.text.trim().length < 6) {
      passwordError = "La password deve essere lunga almeno 6 caratteri";
    }
    else if(_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      passwordError = "Le password devono essere uguali";
      confirmPasswordError = "Le password devono essere uguali";
    }
    else {
      passwordError = null;
      confirmPasswordError = null;
    }
  }

  void validateName() {
    if(_nameController.text.trim().length < 2) {
      nameError = "Il nome non è valido";
    }
    else {
      nameError = null;
    }
  }

  void validateLastName() {
    if(_lastNameController.text.trim().length < 2) {
      lastNameError = "Il cognome non è valido";
    }
    else {
      lastNameError = null;
    }
  }

  void validateNumeroTelefono() {
    final phoneNumber = _numeroTelefonoController.text.trim();
    if (phoneNumber.isNotEmpty) {
      // Verifica che contenga solo numeri
      if (!RegExp(r'^[0-9]+$').hasMatch(phoneNumber)) {
        numeroTelefonoError = "Il numero di telefono deve contenere solo numeri";
      } else if (phoneNumber.length != 10) {
        numeroTelefonoError = "Il numero di telefono deve contenere esattamente 10 cifre";
      } else {
        numeroTelefonoError = null;
      }
    } else {
      numeroTelefonoError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if(validatingEmail) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.email, size: 60, color:onPrimaryColor,),
                  const SizedBox(height: 30,),
                  const Text("Email di conferma inviata!", style: TextStyle(fontSize: 20, color: onPrimaryColor)),
                  const SizedBox(height: 30,),
                  ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(successColor)
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, LOGIN_ROUTE);
                    }, child: const Text("Login", style: TextStyle(color: onPrimaryColor),)
                  )
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: backgroundColor,
        iconTheme: const IconThemeData(color: ghostColor),
        title: const Text("Registrazione", style: TextStyle(color: onPrimaryColor),),
      ),
      backgroundColor: backgroundColor,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Email',),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _emailController, hintText: 'Inserisci la tua email', onTapOutside: (_) => setState(() { validateEmail(); }),),
                  const SizedBox(height: 5,),
                  Text(emailError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Password',),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _passwordController, hintText: 'Inserisci la password', obscureText: true, onTapOutside: (_) => setState(() { validatePassword(); }),),
                  const SizedBox(height: 5,),
                  Text(passwordError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Conferma password',),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _confirmPasswordController, hintText: 'Conferma la password', obscureText: true, onTapOutside: (_) => setState(() { validatePassword(); }),),
                  const SizedBox(height: 5,),
                  Text(confirmPasswordError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Nome',),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _nameController, hintText: 'Inserisci il tuo nome', onTapOutside: (_) => setState(() { validateName(); }),),
                  const SizedBox(height: 5,),
                  Text(nameError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Cognome',),
                  const SizedBox(height: 10,),
                  CustomTextField(controller: _lastNameController, hintText: 'Inserisci il tuo cognome', onTapOutside: (_) => setState(() { validateLastName(); }),),
                  const SizedBox(height: 5,),
                  Text(lastNameError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  const Text('Numero di Telefono (opzionale)',),
                  const SizedBox(height: 10,),
                  CustomTextField(
                    controller: _numeroTelefonoController, 
                    hintText: 'Inserisci il tuo numero di telefono',
                    onTapOutside: (_) => setState(() { validateNumeroTelefono(); }),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                  const SizedBox(height: 5,),
                  Text(numeroTelefonoError ?? '', style: const TextStyle(color: dangerColor),),
        
                  const SizedBox(height: 20,),
                  Row(
                    children: [
                      Checkbox(
                        value: privacyAccepted,
                        onChanged: (value) {
                          setState(() {
                            privacyAccepted = value ?? false;
                          });
                        },
                      ),
                      const Text('Accetto la '),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse('https://www.google.it');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(registrationError ?? '', style: const TextStyle(color: dangerColor),),
              if (privacyError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    privacyError!,
                    style: const TextStyle(color: dangerColor),
                  ),
                ),
              const SizedBox(height: 10,),
              SizedBox(
                width: MediaQuery.of(context).size.width - pagePadding * 2,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      validateName();
                      validateLastName();
                      validateEmail();
                      validatePassword();
                      validateNumeroTelefono();
                      if (!privacyAccepted) {
                        privacyError = 'Devi accettare la privacy policy';
                      } else {
                        privacyError = null;
                      }
                    });

                    if (
                      nameError != null ||
                      lastNameError != null ||
                      emailError != null ||
                      passwordError != null ||
                      confirmPasswordError != null ||
                      numeroTelefonoError != null ||
                      !privacyAccepted
                    ) {
                      return;
                    }

                    registerWithEmailPassword(
                      _emailController.text.trim(),
                      _passwordController.text.trim(),
                      _nameController.text.trim(),
                      _lastNameController.text.trim(),
                      numeroTelefono: _numeroTelefonoController.text.trim().isNotEmpty ? _numeroTelefonoController.text.trim() : null,
                    ).then((SignUpResponse? response) {
                      if (response != null && response.user != null) {
                        store.dispatch(SetUserAction(response.user!));

                        setState(() {
                          validatingEmail = true;
                        });
                      } else {
                        setState(() {
                          registrationError = response!.error;
                        });
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
