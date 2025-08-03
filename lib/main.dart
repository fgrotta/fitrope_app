import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase only if not in test environment
  if (!const bool.fromEnvironment('FLUTTER_TEST')) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Log error but continue with app initialization
      print('Firebase initialization error: $e');
    }
  }

  runApp(SafeArea(
    child: StoreProvider(store: store, child: const MyApp()),
  ));

  // tests();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitRope',
      debugShowCheckedModeBanner: false,
      initialRoute: INITIAL_ROUTE,
      routes: routes,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: child!,
        );
      },
    );
  }
}
