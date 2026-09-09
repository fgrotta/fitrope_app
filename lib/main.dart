import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:fitrope_app/services/onesignal_service.dart';
import 'firebase_options.dart' as prod;
import 'firebase_options_staging.dart';

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
  // Se in IndexedDB c'e' una sessione persistita, l'SDK la ripristina e ne
  // rinnova il token appena l'istanza di Auth nasce — cioe' PRIMA che
  // `useAuthEmulator` faccia effetto. Da quel momento le chiamate di auth
  // vanno al progetto di PRODUZIONE, e la cosa non da' alcun errore: sparisce
  // solo il banner rosso dell'SDK, e l'app riparte gia' su /protected con una
  // sessione che non e' quella dell'emulatore.
  //
  // Partire SEMPRE da slogato toglie di mezzo la sessione che innesca la
  // corsa. In QA non e' un costo: il login sull'emulatore si rifa' a ogni
  // avvio comunque, e i dati sono effimeri.
  await FirebaseAuth.instance.signOut();

  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  // Le callable usano sempre instanceFor(region: 'europe-west8'): l'emulatore
  // va agganciato alla STESSA istanza/region, altrimenti le chiamate andrebbero
  // in produzione.
  FirebaseFunctions.instanceFor(region: 'europe-west8')
      .useFunctionsEmulator(emulatorHost, 5001);
  debugPrint(
      '⚠️ EMULATORE FIREBASE ATTIVO ($emulatorHost) — nessun dato reale');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: isStaging
        ? StagingFirebaseOptions.currentPlatform
        : prod.DefaultFirebaseOptions.currentPlatform,
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
  initItalianTime(); // l'app mostra/salva sempre l'orario italiano (Europe/Rome)

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
      builder: (context, child) => isStaging
          ? Banner(
              message: 'STAGING',
              location: BannerLocation.topStart,
              child: child ?? const SizedBox.shrink(),
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
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', 'US'),
      ],
      initialRoute: INITIAL_ROUTE,
      routes: routes,
    );
  }
}
