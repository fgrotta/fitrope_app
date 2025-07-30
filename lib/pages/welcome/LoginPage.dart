// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/login.dart';
import 'package:fitrope_app/authentication/resendVerificationEmail.dart';
import 'package:fitrope_app/authentication/resetPassword.dart';
import 'package:fitrope_app/components/custom_text_field.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController =
      TextEditingController(text: 'grotta.francesco+admin@gmail.com');
  final TextEditingController _passwordController =
      TextEditingController(text: 'grotta.francesco+admin@gmail.com');
  String? loginError;
  bool emailNotVerified = false;

  @override
  void initState() {
    super.initState();
    if (isLogged()) {
      print("User is logged");
      loggedRedirect(context);
    }
  }

  void onLogin() async {
    SignInResponse? signInResponse = await signInWithEmailPassword(
      _emailController.text,
      _passwordController.text,
    );

    if (signInResponse.user != null) {
      store.dispatch(SetUserAction(signInResponse.user!));
      Navigator.pushNamed(context, PROTECTED_ROUTE);

      setState(() {
        loginError = null;
      });
    } else {
      setState(() {
        loginError = signInResponse.error;

        if (signInResponse.emailNotVerified) {
          emailNotVerified = true;
        }
      });
    }
  }

  void showResetPasswordDialog() {
    final TextEditingController emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: emailController,
            decoration:
                const InputDecoration(hintText: 'Inserisci la tua email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await resetPassword(emailController.text);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email di reset inviata!')),
                  );
                } catch (e) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Errore durante l\'invio')),
                  );
                }
              },
              child: const Text('Invia'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, bool>(
        converter: (store) => store.state.isLoading,
        builder: (context, isLoading) {
          return Stack(
            children: [
              Scaffold(
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    iconTheme: const IconThemeData(color: Colors.white),
                    title: const Text("Login",
                        style: TextStyle(color: Colors.white)),
                  ),
                  backgroundColor: primaryColor,
                  body: Padding(
                    padding: EdgeInsets.only(
                        left: pagePadding,
                        right: pagePadding,
                        bottom: pagePadding,
                        top: pagePadding +
                            MediaQuery.of(context).viewPadding.top),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email',
                              style: TextStyle(color: ghostColor),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            CustomTextField(
                              controller: _emailController,
                              hintText: 'Enter your email',
                            ),
                            const SizedBox(
                              height: 20,
                            ),
                            const Text(
                              'Password',
                              style: TextStyle(color: ghostColor),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            CustomTextField(
                              controller: _passwordController,
                              hintText: 'Enter your password',
                              obscureText: true,
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            if (loginError != null)
                              Text(
                                loginError!,
                                style: const TextStyle(color: dangerColor),
                              ),
                            const SizedBox(
                              height: 10,
                            ),
                            if (emailNotVerified)
                              ElevatedButton(
                                style: ButtonStyle(
                                    backgroundColor: WidgetStateProperty.all(
                                        Colors.blueAccent)),
                                onPressed: () {
                                  resendVerificationEmail();
                                },
                                child: const Text(
                                  'Invia di nuovo email',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            const SizedBox(
                              height: 10,
                            ),
                            GestureDetector(
                              onTap: showResetPasswordDialog,
                              child: const Text('Password dimenticata?',
                                  style: TextStyle(
                                      color: Colors.blueAccent,
                                      decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width -
                              pagePadding * 2,
                          child: ElevatedButton(
                            onPressed: () {
                              onLogin();
                            },
                            style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.all(secondaryColor),
                                shape: WidgetStateProperty.all<
                                        RoundedRectangleBorder>(
                                    RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ))),
                            child: const Text(
                              'Login',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  )),
              if (isLoading) const Loader(),
            ],
          );
        });
  }
}
