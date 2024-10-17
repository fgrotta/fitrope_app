import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/pages/RegistrationPage.dart';
import 'package:flutter/material.dart';

void main() async {  
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp(
  //   options: const FirebaseOptions(
  //     apiKey: "XXX",
  //     appId: "XXX",
  //     messagingSenderId: "XXX",
  //     projectId: "XXX",
  //   ),
  // );
  await Firebase.initializeApp();
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