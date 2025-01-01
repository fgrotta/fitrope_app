import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    if(isLogged()){
      loggedRedirect(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Padding(
        padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fit House Monza', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),),
                Column(
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width - pagePadding * 2,
                      child: ElevatedButton(
                        onPressed: () { Navigator.pushNamed(context, LOGIN_ROUTE); }, 
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(secondaryColor),
                          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            )
                          )
                        ),
                        child: const Text('Entra', style: TextStyle(color: Colors.white),)
                      ),
                    ),
                    const SizedBox(height: 20,),
                    SizedBox(
                      width: MediaQuery.of(context).size.width - pagePadding * 2,
                      child: ElevatedButton(
                        onPressed: () { Navigator.pushNamed(context, REGISTRATION_ROUTE); },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(secondaryColor),
                          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            )
                          )
                        ), 
                        child: const Text('Registrati', style: TextStyle(color: Colors.white),)
                      ),
                    ),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}