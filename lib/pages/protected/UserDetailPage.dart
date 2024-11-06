import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';

class UserDetailPage extends StatefulWidget {
  const UserDetailPage({super.key});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  late FitropeUser user;

  @override
  void initState() {
    user = store.state.user!;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profilo', style: TextStyle(color: Colors.white),),
      ),
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          Text(user.name),
          Text(user.lastName),
          ElevatedButton(onPressed: () {
            signOut().then((_) {
              logoutRedirect(context);
            });
          }, child: const Text('Logout'))
        ],
      ),
    );
  }
}