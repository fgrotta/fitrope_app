// ignore_for_file: constant_identifier_names

import 'package:fitrope_app/pages/protected/Protected.dart';
import 'package:fitrope_app/pages/protected/CourseManagementPage.dart';
import 'package:fitrope_app/pages/welcome/LoginPage.dart';
import 'package:fitrope_app/pages/welcome/RegistrationPage.dart';
import 'package:fitrope_app/pages/welcome/WelcomePage.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/material.dart';

const WELCOME_ROUTE = '/';
const LOGIN_ROUTE = '/login';
const REGISTRATION_ROUTE = '/registration';
const PROTECTED_ROUTE = '/protected';
const COURSE_MANAGEMENT_ROUTE = '/course-management';

const INITIAL_ROUTE = WELCOME_ROUTE;

Map<String, Widget Function(BuildContext)> routes = {
  WELCOME_ROUTE: (context) => const WelcomePage(),
  LOGIN_ROUTE: (context) => const LoginPage(),
  REGISTRATION_ROUTE: (context) => const RegistrationPage(),
  PROTECTED_ROUTE: (context) => const Protected(),
  COURSE_MANAGEMENT_ROUTE: (context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final courseToEdit = args?['courseToEdit'] as Course?;
    final courseToDuplicate = args?['courseToDuplicate'] as Course?;
    final mode = args?['mode'] as String? ?? 'create';
    
    return CourseManagementPage(
      courseToEdit: courseToEdit,
      courseToDuplicate: courseToDuplicate,
      mode: mode,
    );
  },
};