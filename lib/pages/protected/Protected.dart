import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/layout/app_shell.dart';
import 'package:fitrope_app/pages/protected/CalendarPage.dart';
import 'package:fitrope_app/pages/protected/Homepage.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/pages/protected/AdminDashboardPage.dart';
import 'package:fitrope_app/pages/protected/AdminUsersPage.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class Protected extends StatefulWidget {
  const Protected({super.key});

  @override
  State<Protected> createState() => _ProtectedState();
}

class _ProtectedState extends State<Protected> {
  late FitropeUser? user = store.state.user;
  int currentIndex = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _drawerTitle;
  List<FitropeUser>? _drawerUsers;

  void _openUserList(String title, List<FitropeUser> users) {
    setState(() {
      _drawerTitle = title;
      _drawerUsers = users;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

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

  int _getMaxIndex(BuildContext context) {
    final admin = user?.role == 'Admin';
    if (isDesktop(context) && admin) return 3;
    if (admin) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final maxIndex = _getMaxIndex(context);

    if (!desktop && currentIndex == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => currentIndex = 2);
      });
    }

    final effectiveIndex = currentIndex.clamp(0, maxIndex);

    return StoreConnector<AppState, bool>(
      converter: (store) => store.state.isLoading,
      builder: (context, isLoading) {
        return Theme(
          data: Theme.of(context).copyWith(
            drawerTheme: DrawerThemeData(
              width: 400,
              elevation: 16,
            ),
          ),
          child: Scaffold(
            key: _scaffoldKey,
            endDrawer: _drawerTitle != null && _drawerUsers != null
                ? UserListDrawer(
                    title: _drawerTitle!,
                    users: _drawerUsers!,
                    onClose: () => setState(() {
                      _drawerTitle = null;
                      _drawerUsers = null;
                    }),
                  )
                : null,
            body: Stack(
              children: [
                AppShell(
                  currentIndex: effectiveIndex,
                  isAdmin: user?.role == 'Admin',
                  onChangePage: (index) {
                    setState(() {
                      currentIndex = index;
                    });
                  },
                  child: user != null ? _getPageFor(effectiveIndex) : const SizedBox.shrink(),
                ),
                if (isLoading) const Loader(),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _getPageFor(int index) {
    switch(index) {
      case 0: return const HomePage();
      case 1: return const CalendarPage();
      case 2: return const AdminUsersPage();
      case 3: return AdminDashboardPage(onOpenUserList: _openUserList);
      default: return const HomePage();
    }
  }
}