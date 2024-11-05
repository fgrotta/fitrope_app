import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/pages/protected/GymsPage.dart';
import 'package:fitrope_app/pages/protected/Homepage.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_bottom_navigation_bar.dart';

class Protected extends StatefulWidget {
  const Protected({super.key});

  @override
  State<Protected> createState() => _ProtectedState();
}

class _ProtectedState extends State<Protected> {
  late FitropeUser? user = store.state.user;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if(!isLogged()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(LOGIN_ROUTE);
      });
    }
    else {
      if(user != null) {
        print("${user!.name} ${user!.lastName} logged");
      }
      else {
        resetUser();
      }
    }
  }

  Future<void> resetUser() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    Map<String, dynamic>? userData = await getUserData(uid);

    if(userData != null) {
      setState(() {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
        user = store.state.user;
        print("${user!.name} ${user!.lastName} logged");
      });
    }
    else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(LOGIN_ROUTE);
      });
    }
  }

  Widget getPage() {
    switch(currentIndex) {
      case 0: return const HomePage();
      case 1: return const GymsPage();
      default: return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {    
    return Scaffold(
      backgroundColor: backgroundColor,
      bottomNavigationBar: CustomBottomNavigationBar(
        items: const [
          CustomBottomNavigationBarItem(icon: Icons.home, label: 'Home'),
          CustomBottomNavigationBarItem(icon: Icons.list, label: 'Gyms'),
        ], 
        colors: const CustomBottomNavigationBarColors(
          backgroundColor: primaryColor, 
          selectedItemColor: Colors.white, 
          unselectedItemColor: ghostColor,
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
          getPage(),
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