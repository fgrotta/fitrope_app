import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';

class Protected extends StatefulWidget {
  const Protected({super.key});

  @override
  State<Protected> createState() => _ProtectedState();
}

class _ProtectedState extends State<Protected> {
  @override
  void initState() {
    super.initState();
    if(!isLogged()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(LOGIN_ROUTE);
      });
    }
  }

  @override
  Widget build(BuildContext context) {    
    return const Scaffold(
      body: Column(
        children: [
          Text('Protected')
        ],
      ),
    );
  }
}