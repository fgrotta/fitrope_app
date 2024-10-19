import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/api/getGyms.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

void main() async {  
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());


  // tests //
  // dynamic gyms = await getGyms();
  // print(gyms[0].name);
  // tests //
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: INITIAL_ROUTE,
      routes: routes,
    );
  }
}