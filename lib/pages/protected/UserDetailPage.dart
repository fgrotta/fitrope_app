import 'package:fitrope_app/authentication/deleteUser.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/components/custom_text_field.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nome', style: TextStyle(color: ghostColor),),
            const SizedBox(height: 10,),
            CustomTextField(controller: TextEditingController(text: user.name), disabled: true,),
            const SizedBox(height: 20,),

            const Text('Cognome', style: TextStyle(color: ghostColor),),
            const SizedBox(height: 10,),
            CustomTextField(controller: TextEditingController(text: user.lastName), disabled: true,),
            const SizedBox(height: 20,),

            if(user.fineIscrizione != null) ...[
              const Text('Fine iscrizione', style: TextStyle(color: ghostColor),),
              const SizedBox(height: 10,),
              CustomTextField(controller: TextEditingController(text: formatDate(DateTime.fromMillisecondsSinceEpoch(user.fineIscrizione!.millisecondsSinceEpoch))), disabled: true,),
            ],

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
            ),

            const SizedBox(height: 20,),
            ElevatedButton(
              onPressed: () {
                showDialog(context: context, builder:(context) => AlertDialog(
                  backgroundColor: primaryColor,
                  title: const Text('Elimina Account', style: TextStyle(color: Colors.white),),
                  content: const Text('Sei sicuro di voler eliminare il tuo account?', style: TextStyle(color: Colors.white),),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      }, 
                      child: const Text('Annulla', style: TextStyle(color: Colors.white),),
                    ),
                    TextButton(
                      onPressed: () {
                        deleteUser().then((_) {
                          logoutRedirect(context);
                        });
                      }, 
                      child: const Text('Elimina', style: TextStyle(color: Colors.white),),
                    )
                  ],
                ));
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(const Color.fromARGB(255, 230, 34, 34)),
                padding: WidgetStateProperty.all(const EdgeInsets.only(top: 0, left: 10, right: 10, bottom: 0)),
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  )
                )
              ), 
              child: const Text('Elimina Account', style: TextStyle(color: Colors.white),)
            )
          ],
        ),
      ),
    );
  }
}