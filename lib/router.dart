// ignore_for_file: constant_identifier_names

// Pagine dell'area protetta caricate in modo DIFFERITO (deferred loading): non
// entrano nel bundle iniziale (login/welcome), vengono scaricate alla prima
// navigazione o pre-caricate durante lo splash (vedi SplashScreen). Le welcome
// page restano eager. Ogni prefisso = un chunk; il codice condiviso viene
// deduplicato dal compilatore.
import 'package:fitrope_app/pages/protected/protected.dart'
    deferred as protected;
import 'package:fitrope_app/pages/protected/course_management_page.dart'
    deferred as course_management;
import 'package:fitrope_app/pages/protected/debug_email_page.dart'
    deferred as debug_email;
import 'package:fitrope_app/pages/protected/recurring_course_page.dart'
    deferred as recurring_course;
import 'package:fitrope_app/pages/welcome/login_page.dart';
import 'package:fitrope_app/pages/welcome/registration_page.dart';
import 'package:fitrope_app/pages/welcome/welcome_page.dart';
import 'package:fitrope_app/components/deferred_page.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/pages/welcome/splash_screen.dart';

const WELCOME_ROUTE = '/';
const LOGIN_ROUTE = '/login';
const REGISTRATION_ROUTE = '/registration';
const PROTECTED_ROUTE = '/protected';
const COURSE_MANAGEMENT_ROUTE = '/course-management';
const RECURRING_COURSE_ROUTE = '/recurring-course';
const SPLASH_ROUTE = '/splash';
const DEBUG_EMAIL_ROUTE = '/debug-email';

const INITIAL_ROUTE = SPLASH_ROUTE;

Map<String, Widget Function(BuildContext)> routes = {
  SPLASH_ROUTE: (context) => Title(
      color: Colors.black, title: 'Fit House', child: const SplashScreen()),
  WELCOME_ROUTE: (context) => Title(
      color: Colors.black,
      title: 'Fit House - Welcome',
      child: const WelcomePage()),
  LOGIN_ROUTE: (context) => Title(
      color: Colors.black,
      title: 'Fit House - Login',
      child: const LoginPage()),
  REGISTRATION_ROUTE: (context) => Title(
      color: Colors.black,
      title: 'Fit House - Registrazione',
      child: const RegistrationPage()),
  PROTECTED_ROUTE: (context) => Title(
      color: Colors.black,
      title: 'Fit House',
      child: DeferredPage(
        load: protected.loadLibrary,
        builder: (_) => protected.Protected(),
      )),
  RECURRING_COURSE_ROUTE: (context) => Title(
      color: Colors.black,
      title: 'Fit House - Gestione Corso',
      child: DeferredPage(
        load: recurring_course.loadLibrary,
        builder: (_) => recurring_course.RecurringCoursePage(),
      )),
  if (kDebugMode)
    DEBUG_EMAIL_ROUTE: (context) => DeferredPage(
          load: debug_email.loadLibrary,
          builder: (_) => debug_email.DebugEmailPage(),
        ),
  COURSE_MANAGEMENT_ROUTE: (context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final courseToEdit = args?['courseToEdit'] as Course?;
    final courseToDuplicate = args?['courseToDuplicate'] as Course?;
    final mode = args?['mode'] as String? ?? 'create';

    return Title(
      color: Colors.black,
      title: 'Fit House - Gestione Corso',
      child: DeferredPage(
        load: course_management.loadLibrary,
        builder: (_) => course_management.CourseManagementPage(
          courseToEdit: courseToEdit,
          courseToDuplicate: courseToDuplicate,
          mode: mode,
        ),
      ),
    );
  },
};
