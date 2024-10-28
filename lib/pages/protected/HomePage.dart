import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.white),),
              CircleAvatar(
                backgroundColor: Color.fromARGB(255, 113, 129, 219),
                child: Text('AH'),
              )
            ],
          ),
        ],
      ),
    );
  }
}