import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/api/get_user_data.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:fitrope_app/authentication/is_logged.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/components/push_enable_banner.dart';
import 'package:fitrope_app/services/push_environment.dart';
import 'package:fitrope_app/utils/push_prompt_prefs.dart';
import 'package:fitrope_app/layout/app_shell.dart';
import 'package:fitrope_app/pages/protected/calendar_page.dart';
import 'package:fitrope_app/pages/protected/home_page.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/pages/protected/admin_dashboard_page.dart';
import 'package:fitrope_app/pages/protected/admin_users_page.dart';
import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/simulation_guard.dart';
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

  /// Banner "questo dispositivo non riceve le notifiche". Calcolato da
  /// [_evaluatePushPrompt], mai dentro `_syncOneSignalIdentity` — quello resta
  /// l'unico punto che parla di *identità* con OneSignal.
  PushPromptDecision _pushPrompt = PushPromptDecision.hidden;

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
    });

    if (!isLogged()) {
      // Unica via alla schermata di login che NON passa da `signOut()` (che
      // in simulazione lancia): Firebase ha invalidato la sessione dell'admin.
      // Una simulazione lasciata viva qui farebbe fallire il login successivo,
      // perché anche `signInWithEmailPassword` asserisce.
      SimulationSession.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(LOGIN_ROUTE);
      });
    } else {
      if (user != null) {
        debugPrint("${user!.name} ${user!.lastName} logged");
        _syncOneSignalIdentity(user!);
        unawaited(_evaluatePushPrompt());
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

    final courses = await getAllCourses(force: true);
    if (!mounted) return;
    setState(() {
      store.dispatch(SetAllCoursesAction(courses));
    });

    // Propaga il refresh a HomePage / pagine admin e alle card iscritti.
    RefreshManager().notifyRefresh();
  }

  /// Lega il device all'identità corrente su OneSignal. UNICO punto in
  /// `Protected` che chiama OneSignal: chi aggiunge una chiamata di identità
  /// la mette qui, così la guardia sotto vale una volta sola.
  ///
  /// MODALITÀ SIMULAZIONE: dopo il remount `user` è l'utente SIMULATO. Senza
  /// questa uscita il device dell'admin verrebbe registrato su OneSignal come
  /// quel socio, con la sua email agganciata e le sue preferenze push
  /// applicate (e le guardie in `OneSignalService` lancerebbero da initState).
  /// Regola: in simulazione non si chiama mai OneSignal.
  void _syncOneSignalIdentity(FitropeUser u) {
    if (SimulationSession.isActive) return;
    // Fire-and-forget esplicito: le chiamate ritornano Future vere (il bridge
    // web ora restituisce Promise), ma questo è un percorso di boot e non deve
    // attendere il round-trip verso OneSignal.
    unawaited(OneSignalService.login(u.uid));
    if (u.email.isNotEmpty) {
      unawaited(OneSignalService.addEmail(u.email));
    }
    unawaited(OneSignalService.syncPushPreference(u.pushNotificationsEnabled));
  }

  /// Decide se mostrare il banner push per **questo dispositivo**.
  ///
  /// In simulazione non parte nulla: `pushEnvironment()` non tocca l'identità,
  /// ma il bottone "Attiva" chiamerebbe `requestPushPermission()`, che è
  /// guardato e lancerebbe.
  Future<void> _evaluatePushPrompt() async {
    final u = user;
    if (u == null || SimulationSession.isActive) {
      if (mounted && _pushPrompt != PushPromptDecision.hidden) {
        setState(() => _pushPrompt = PushPromptDecision.hidden);
      }
      return;
    }

    final env = await OneSignalService.pushEnvironment();
    if (!mounted) return;

    // Due passate: la chiave dello snooze dipende da *quale* banner mostreremmo,
    // quindi serve prima il candidato e poi la decisione definitiva.
    final candidate = decidePushPrompt(
      env: env,
      preferenceEnabled: u.pushNotificationsEnabled,
      simulating: false,
      snoozed: false,
    );
    final decision = decidePushPrompt(
      env: env,
      preferenceEnabled: u.pushNotificationsEnabled,
      simulating: false,
      snoozed: candidate != PushPromptDecision.hidden &&
          isPushPromptSnoozed(candidate.name),
    );

    if (decision != _pushPrompt) {
      setState(() => _pushPrompt = decision);
    }
  }

  /// Bottone "Attiva" del banner: `requestPushPermission()` è la **prima**
  /// istruzione, senza await interposti, o su WebKit il prompt non compare.
  ///
  /// Un diniego non scrive mai `pushNotificationsEnabled = false` su Firestore:
  /// è un flag cross-device, un rifiuto su questo browser non deve spegnere le
  /// push sugli altri dispositivi dell'utente.
  void _activatePush() {
    final granted = OneSignalService.requestPushPermission();
    unawaited(granted.then((_) => _evaluatePushPrompt()));
  }

  void _dismissPushPrompt() {
    snoozePushPrompt(_pushPrompt.name, snoozeDurationFor(_pushPrompt));
    setState(() => _pushPrompt = PushPromptDecision.hidden);
  }

  Future<void> resetUser() async {
    // In simulazione questo metodo rileggerebbe `FirebaseAuth.currentUser.uid`
    // — che è sempre l'ADMIN — e terminerebbe la simulazione di nascosto,
    // sostituendo l'utente nello store mentre la barra resta accesa.
    if (SimulationSession.isActive) return;

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
        _syncOneSignalIdentity(user!);
        unawaited(_evaluatePushPrompt());
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
                  Column(
                    children: [
                      if (_pushPrompt != PushPromptDecision.hidden)
                        PushEnableBanner(
                          decision: _pushPrompt,
                          onDismiss: _dismissPushPrompt,
                          // Niente "Attiva" in tab Safari su iOS: l'API non
                          // esiste finché la PWA non è installata.
                          onActivate:
                              _pushPrompt == PushPromptDecision.canRequest
                                  ? _activatePush
                                  : null,
                        ),
                      Expanded(
                        child: AppShell(
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
                                      builder: (context) =>
                                          UserDetailPage(user: u),
                                    ),
                                  );
                                }
                              : null,
                          onLogout: () async {
                            if (SimulationGuard.blockIfSimulating(context)) {
                              return;
                            }
                            await signOut();
                            if (!context.mounted) return;
                            logoutRedirect(context);
                          },
                          child: user != null
                              ? _getPageFor(effectiveIndex)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
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
