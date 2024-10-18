// ignore_for_file: use_build_context_synchronously

import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_bottom_navigation_bar.dart';

class Protected extends StatefulWidget {
  const Protected({super.key});

  @override
  State<Protected> createState() => _ProtectedState();
}

class _ProtectedState extends State<Protected> {
  int currentIndex = 0;

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
    return Scaffold(
      bottomNavigationBar: CustomBottomNavigationBar(
        items: const [
          CustomBottomNavigationBarItem(icon: Icons.home, label: 'Home'),
          CustomBottomNavigationBarItem(icon: Icons.list, label: 'Gyms'),
        ], 
        colors: const CustomBottomNavigationBarColors(
          backgroundColor: Colors.black, 
          selectedItemColor: Colors.blue, 
          unselectedItemColor: Colors.red,
        ), 
        onChangePage: (int index) {
          setState(() {
            currentIndex = index;
          });
        }, 
        currentIndex: currentIndex, 
      ),
      body: Column(
        children: [
          const Text('Protected'),
          ElevatedButton(onPressed: () {
            signOut().then((_) {
              logoutRedirect(context);
            });
          }, child: const Text('Logout'))
        ],
      ),
    );
  }
}