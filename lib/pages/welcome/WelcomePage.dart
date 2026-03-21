import 'package:fitrope_app/authentication/isLogged.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
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
      backgroundColor: backgroundColor,
      body: Padding(
        padding: EdgeInsets.only(
          left: isDesktop(context) ? MediaQuery.of(context).size.width * 0.40 : pagePadding,
          right: isDesktop(context) ? MediaQuery.of(context).size.width * 0.40 : pagePadding,
          bottom: pagePadding,
          top: pagePadding + 12.5 + MediaQuery.of(context).viewPadding.top,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Image(image: AssetImage('assets/new_logo_only.png'), width: 200),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: () { Navigator.pushNamed(context, LOGIN_ROUTE); }, 
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(ghostColor),
                    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      )
                    )
                  ),
                  child: const Text('Entra', style: TextStyle(color: surfaceVariantColor),)
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () { Navigator.pushNamed(context, REGISTRATION_ROUTE); },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(ghostColor),
                    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      )
                    )
                  ), 
                  child: const Text('Registrati', style: TextStyle(color: surfaceVariantColor),)
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}