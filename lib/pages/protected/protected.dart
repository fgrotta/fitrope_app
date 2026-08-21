import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/api/get_user_data.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:fitrope_app/authentication/is_logged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/layout/app_shell.dart';
import 'package:fitrope_app/pages/protected/calendar_page.dart';
import 'package:fitrope_app/pages/protected/home_page.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/pages/protected/admin_dashboard_page.dart';
import 'package:fitrope_app/pages/protected/admin_users_page.dart';
import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:fitrope_app/services/onesignal_service.dart';

class Protected extends StatefulWidget {
  const Protected({super.key});

  @override
  State<Protected> createState() => _ProtectedState();
}

class _ProtectedState extends State<Protected> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);

    getAllCourses().then((List<Course> response) {
      if (mounted) {
        setState(() {
          store.dispatch(SetAllCoursesAction(response));
        });
      }
    }).catchError((Object error) {
      // La richiesta può terminare dopo logout/dispose. Non lasciare una Future
      // non gestita che faccia cadere l'app o il caso E2E successivo.
      debugPrint('Errore nel caricamento iniziale dei corsi: $error');
    });

    if (!isLogged()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(LOGIN_ROUTE);
      });
    } else {
      if (user != null) {
        debugPrint("${user!.name} ${user!.lastName} logged");
        OneSignalService.login(user!.uid);
        if (user!.email.isNotEmpty) {
          OneSignalService.addEmail(user!.email);
        }
        OneSignalService.syncPushPreference(user!.pushNotificationsEnabled);
      } else {
        resetUser();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumeRefresh();
    }
  }

  /// Alla ripresa dell'app invalida le cache in-memory e ricarica i dati,
  /// così la lista corsi/iscritti riflette lo stato corrente del server
  /// (vale su tutti i dispositivi/browser).
  Future<void> _onResumeRefresh() async {
    invalidateCoursesCache();
    invalidateAllUserCaches();

    try {
      final courses = await getAllCourses(force: true);
      if (!mounted) return;
      setState(() {
        store.dispatch(SetAllCoursesAction(courses));
      });

      // Propaga il refresh a HomePage / pagine admin e alle card iscritti.
      RefreshManager().notifyRefresh();
    } catch (error) {
      // Un resume può sovrapporsi al logout o al dispose della pagina.
      debugPrint('Errore nel refresh corsi alla ripresa: $error');
    }
  }

  Future<void> resetUser() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    Map<String, dynamic>? userData = await getUserData(uid);
    if (!mounted) return;

    if (userData != null) {
      setState(() {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
        user = store.state.user;
        debugPrint("${user!.name} ${user!.lastName} logged");
      });
      if (user != null) {
        OneSignalService.login(user!.uid);
        if (user!.email.isNotEmpty) {
          OneSignalService.addEmail(user!.email);
        }
        OneSignalService.syncPushPreference(user!.pushNotificationsEnabled);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        signOut().then((_) {
          if (!mounted) return;
          logoutRedirect(context);
        });
      });
    }
  }

  String? _userProfileInitials(FitropeUser? u) {
    if (u == null) return null;
    final a = u.name.isNotEmpty ? u.name[0] : '';
    final b = u.lastName.isNotEmpty ? u.lastName[0] : '';
    final s = '$a$b';
    return s.isEmpty ? '?' : s;
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
              drawerTheme: const DrawerThemeData(
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
              floatingActionButton: kDebugMode
                  ? FloatingActionButton.small(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(DEBUG_EMAIL_ROUTE),
                      tooltip: 'Debug email',
                      child: const Icon(Icons.bug_report_outlined),
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
                    profileInitials:
                        desktop ? _userProfileInitials(user) : null,
                    onProfileTap: desktop && user != null
                        ? () {
                            final u = user!;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => UserDetailPage(user: u),
                              ),
                            );
                          }
                        : null,
                    onLogout: () async {
                      await signOut();
                      if (!context.mounted) return;
                      logoutRedirect(context);
                    },
                    child: user != null
                        ? _getPageFor(effectiveIndex)
                        : const SizedBox.shrink(),
                  ),
                  if (isLoading) const Loader(),
                ],
              ),
            ),
          );
        });
  }

  Widget _getPageFor(int index) {
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return const CalendarPage();
      case 2:
        return const AdminUsersPage();
      case 3:
        return AdminDashboardPage(onOpenUserList: _openUserList);
      default:
        return const HomePage();
    }
  }
}
