import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/pages/protected/CalendarPage.dart';
import 'package:fitrope_app/pages/protected/Homepage.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_bottom_navigation_bar.dart';
import 'package:flutter_redux/flutter_redux.dart';

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

    getAllCourses().then((List<Course> response) {
      if(mounted) {
        setState(() {
          store.dispatch(SetAllCoursesAction(response));
        });
      }
    });
    
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
        signOut().then((_) {
          logoutRedirect(context);
        }); 
      });
    }
  }

  Widget getPage() {
    switch(currentIndex) {
      case 0: return const HomePage();
      case 1: return const CalendarPage();
      default: return const HomePage();
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
              backgroundColor: backgroundColor,
              bottomNavigationBar: CustomBottomNavigationBar(
                items: const [
                  CustomBottomNavigationBarItem(icon: Icons.home, label: 'Home'),
                  CustomBottomNavigationBarItem(icon: Icons.calendar_month, label: 'Calendario'),
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
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    if(user != null) getPage(),
                  ],
                ),
              ),
            ),
            if (isLoading) const Loader(),
          ]
        );
      }
    );
  }
}