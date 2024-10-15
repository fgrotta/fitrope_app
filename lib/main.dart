import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';
import 'package:flutter_design_system/context.dart';

void main() {
  PartialContext partialContext = const PartialContext(
    backgroundColor: Colors.yellow,
    primaryColor: Colors.black
  );
  Context.mergeContext(partialContext);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            CustomCard(title: 'asd',)
          ],
        ),
      )
    );
  }
}