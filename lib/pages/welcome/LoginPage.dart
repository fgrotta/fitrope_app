// ignore_for_file: use_build_context_synchronously
import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/login.dart';
import 'package:fitrope_app/components/custom_text_field.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if(isLogged()){
      loggedRedirect(context);
    }
  }

  void onLogin() async {
    FitropeUser? userData = await signInWithEmailPassword(
      _emailController.text,
      _passwordController.text,
    );

    if(userData != null) {
      store.dispatch(SetUserAction(userData));
      Navigator.pushNamed(context, PROTECTED_ROUTE);
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
    );
  }
}