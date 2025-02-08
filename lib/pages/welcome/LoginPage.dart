// ignore_for_file: use_build_context_synchronously
import 'dart:math';

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/login.dart';
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? loginError;

  @override
  void initState() {
    super.initState();
    if(isLogged()){
      print("User is logged");
      loggedRedirect(context);
    }
  }

  void onLogin() async {
    SignInResponse? signInResponse = await signInWithEmailPassword(
      _emailController.text,
      _passwordController.text,
    );

    if(signInResponse.user != null) {
      store.dispatch(SetUserAction(signInResponse.user!));
      Navigator.pushNamed(context, PROTECTED_ROUTE);

      setState(() {
        loginError = null;
      });
    }
    else {
      setState(() {
        loginError = signInResponse.error;
      });
    }
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
                title: const Text("Login", style: TextStyle(color: Colors.white)),
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
                        CustomTextField(controller: _emailController, hintText: 'Enter your email',),
                        const SizedBox(height: 20,),
                        const Text('Password', style: TextStyle(color: ghostColor),),
                        const SizedBox(height: 10,),
                        CustomTextField(controller: _passwordController, hintText: 'Enter your password', obscureText: true,),
                        const SizedBox(height: 10,),
                        if(loginError != null) Text(loginError!, style: const TextStyle(color: dangerColor),) 
                      ],
                    ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width - pagePadding * 2,
                      child: ElevatedButton(
                        onPressed: () {
                          onLogin();
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(secondaryColor),
                          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            )
                          )
                        ), 
                        child: const Text('Login', style: TextStyle(color: Colors.white),),
                      ),
                    )
                  ],
                ),
              )
            ),
            if (isLoading) const Loader(),
          ],
        );
      }
    );
  }
}