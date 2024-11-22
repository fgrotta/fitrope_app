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
      body: Padding(
        padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
        child: Column(
          children: [
            TextField(
              readOnly: true,
              controller: TextEditingController(text: user.name),
              style: const TextStyle(color: ghostColor),
              canRequestFocus: false,
            ),
            TextField(
              readOnly: true,
              controller: TextEditingController(text: user.lastName),
              style: const TextStyle(color: ghostColor),
              canRequestFocus: false,
            ),
            const SizedBox(height: 20,),
            ElevatedButton(
              onPressed: () {
                signOut().then((_) {
                  logoutRedirect(context);
                }); 
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(primaryColor),
                padding: WidgetStateProperty.all(const EdgeInsets.only(top: 0, left: 10, right: 10, bottom: 0)),
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  )
                )
              ), 
              child: const Text('Logout', style: TextStyle(color: Colors.white),)
            )
          ],
        ),
      ),
    );
  }
}