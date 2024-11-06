import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FitropeUser user;

  @override
  void initState() {
    user = store.state.user!;
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.white),),
              GestureDetector(
                child: CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 113, 129, 219),
                  child: Text(user.name[0] + user.lastName[0]),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserDetailPage()),
                  );
                },
              )
            ],
          ),
        ],
      ),
    );
  }
}