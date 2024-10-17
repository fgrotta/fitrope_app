import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/pages/RegistrationPage.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

void main() async {  
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: RegistrationPage()
        // body: Column(
        //   children: [
        //     Text('test', style: TextStyle(color: Colors.white),)
        //   ],
        // ),
      )
    );
  }
}