import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fitrope_app/services/onesignal_service.dart';
import 'firebase_options.dart';

// TODO: Sostituire con il tuo OneSignal App ID dalla dashboard
const String oneSignalAppId = '154fc17b-3ef8-4421-a1e6-466172fa48db';

/// Ambiente di test locale (Firebase Emulator Suite). Avvio:
///   firebase emulators:start
///   flutter run -d chrome --dart-define=USE_EMULATOR=true
/// Da device fisico sulla LAN aggiungere --dart-define=EMULATOR_HOST=<IP Mac>.
/// Vedi docs/AMBIENTI_DI_TEST.md.
const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');
const String emulatorHost =
    String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

Future<void> _connectToEmulators() async {
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  // Le callable usano sempre instanceFor(region: 'europe-west8'): l'emulatore
  // va agganciato alla STESSA istanza/region, altrimenti le chiamate andrebbero
  // in produzione.
  FirebaseFunctions.instanceFor(region: 'europe-west8')
      .useFunctionsEmulator(emulatorHost, 5001);
  debugPrint('⚠️ EMULATORE FIREBASE ATTIVO ($emulatorHost) — nessun dato reale');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (useEmulator) {
    await _connectToEmulators();
  } else {
    // In modalità emulatore OneSignal NON va inizializzato: su device fisico
    // registrerebbe il device (e al login gli utenti seed) sull'app OneSignal
    // di PRODUZIONE, rompendo l'isolamento del QA.
    OneSignalService.initialize(oneSignalAppId);
  }

  await initializeDateFormatting('it_IT', null);

  runApp(SafeArea(
    child: StoreProvider(store: store, child: const MyApp()),
  ));

  // tests();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fit House',
      theme: ThemeData.light(),
      locale: const Locale('it', 'IT'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', 'US'),
      ],
      initialRoute: INITIAL_ROUTE,
      routes: routes,
    );
  }
}
