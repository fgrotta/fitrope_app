// ignore_for_file: constant_identifier_names

import 'package:fitrope_app/pages/protected/Protected.dart';
import 'package:fitrope_app/pages/protected/CourseManagementPage.dart';
import 'package:fitrope_app/pages/welcome/LoginPage.dart';
import 'package:fitrope_app/pages/welcome/RegistrationPage.dart';
import 'package:fitrope_app/pages/welcome/WelcomePage.dart';
import 'package:fitrope_app/pages/protected/RecurringCoursePage.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/pages/welcome/SplashScreen.dart';


const WELCOME_ROUTE = '/';
const LOGIN_ROUTE = '/login';
const REGISTRATION_ROUTE = '/registration';
const PROTECTED_ROUTE = '/protected';
const COURSE_MANAGEMENT_ROUTE = '/course-management';
const RECURRING_COURSE_ROUTE = '/recurring-course';
const SPLASH_ROUTE = '/splash';

const INITIAL_ROUTE = SPLASH_ROUTE;

Map<String, Widget Function(BuildContext)> routes = {
  SPLASH_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House', child: const SplashScreen()),
  WELCOME_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Welcome', child: const WelcomePage()),
  LOGIN_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Login', child: const LoginPage()),
  REGISTRATION_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Registrazione', child: const RegistrationPage()),
  PROTECTED_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House', child: const Protected()),
  RECURRING_COURSE_ROUTE: (context) => Title(color: Colors.black, title: 'Fit House - Gestione Corso', child: const RecurringCoursePage()),
  COURSE_MANAGEMENT_ROUTE: (context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final courseToEdit = args?['courseToEdit'] as Course?;
    final courseToDuplicate = args?['courseToDuplicate'] as Course?;
    final mode = args?['mode'] as String? ?? 'create';
    
    return Title(
      color: Colors.black,
      title: 'Fit House - Gestione Corso',
      child: CourseManagementPage(
        courseToEdit: courseToEdit,
        courseToDuplicate: courseToDuplicate,
        mode: mode,
      ),
    );
  },
};