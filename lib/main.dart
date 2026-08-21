import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/firebase_bootstrap.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeApplicationServices();

  runApp(
    SafeArea(
      child: StoreProvider(store: store, child: const MyApp()),
    ),
  );

  // tests();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => isStaging
          ? Semantics(
              container: true,
              label: 'Ambiente STAGING',
              child: Banner(
                message: 'STAGING',
                location: BannerLocation.topStart,
                child: child ?? const SizedBox.shrink(),
              ),
            )
          : child ?? const SizedBox.shrink(),
      title: 'Fit House',
      theme: ThemeData.light(),
      locale: const Locale('it', 'IT'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('it', 'IT'), Locale('en', 'US')],
      initialRoute: INITIAL_ROUTE,
      routes: routes,
    );
  }
}
