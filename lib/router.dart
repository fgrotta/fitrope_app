// ignore_for_file: constant_identifier_names

import 'package:fitrope_app/components/deferred_page.dart';
import 'package:fitrope_app/pages/protected/Protected.dart';
import 'package:fitrope_app/pages/welcome/LoginPage.dart';
import 'package:fitrope_app/pages/welcome/RegistrationPage.dart';
import 'package:fitrope_app/pages/welcome/WelcomePage.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/pages/welcome/SplashScreen.dart';

// Pagine pesanti e raramente usate: caricate on-demand (deferred) per ridurre il
// main.dart.js iniziale. dart2js le emette in chunk *.part.js separati.
import 'package:fitrope_app/pages/protected/CourseManagementPage.dart' deferred as course_management;
import 'package:fitrope_app/pages/protected/DebugEmailPage.dart' deferred as debug_email;
import 'package:fitrope_app/pages/protected/RecurringCoursePage.dart' deferred as recurring_course;


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
  SPLASH_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House', child: const SplashScreen()),
  WELCOME_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Welcome', child: const WelcomePage()),
  LOGIN_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Login', child: const LoginPage()),
  REGISTRATION_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Registrazione', child: const RegistrationPage()),
  PROTECTED_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House', child: const Protected()),
  RECURRING_COURSE_ROUTE: (context) => Title(
    color: Colors.black,
    title: 'Fit House - Gestione Corso',
    child: DeferredPage(
      loader: recurring_course.loadLibrary,
      builder: (_) => recurring_course.RecurringCoursePage(),
    ),
  ),
  if (kDebugMode) DEBUG_EMAIL_ROUTE: (context) => DeferredPage(
    loader: debug_email.loadLibrary,
    builder: (_) => debug_email.DebugEmailPage(),
  ),
  COURSE_MANAGEMENT_ROUTE: (context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final courseToEdit = args?['courseToEdit'] as Course?;
    final courseToDuplicate = args?['courseToDuplicate'] as Course?;
    final mode = args?['mode'] as String? ?? 'create';

    return Title(
      color: Colors.black,
      title: 'Fit House - Gestione Corso',
      child: DeferredPage(
        loader: course_management.loadLibrary,
        builder: (_) => course_management.CourseManagementPage(
          courseToEdit: courseToEdit,
          courseToDuplicate: courseToDuplicate,
          mode: mode,
        ),
      ),
    );
  },
};