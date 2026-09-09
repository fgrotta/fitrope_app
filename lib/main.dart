import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/utils/clear_auth_persistence.dart';
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

/// Credenziali con cui entrare da soli in modalità emulatore, per non passare
/// dal form a ogni avvio: la persistenza viene azzerata a ogni caricamento
/// (vedi `clearFirebaseAuthPersistence`), quindi il login andrebbe rifatto
/// ogni volta a mano.
///
/// Vuote per default: l'autologin si attiva solo passando i `--dart-define`, e
/// comunque **solo** se `useEmulator` è true. In una build di produzione
/// `useEmulator` è una costante false, quindi il ramo viene eliminato dal
/// tree-shaking e queste stringhe non finiscono nel bundle.
const String emulatorAutologinEmail =
    String.fromEnvironment('EMULATOR_AUTOLOGIN_EMAIL');
const String emulatorAutologinPassword =
    String.fromEnvironment('EMULATOR_AUTOLOGIN_PASSWORD');

/// Entra con le credenziali seed. Non blocca l'avvio se fallisce: un errore
/// qui è un problema del seed o dell'emulatore, non dell'app, e conviene
/// vedere la schermata di login con il suo messaggio piuttosto che un crash.
Future<void> _autologin() async {
  if (emulatorAutologinEmail.isEmpty || emulatorAutologinPassword.isEmpty) {
    return;
  }
  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: emulatorAutologinEmail,
      password: emulatorAutologinPassword,
    );
    debugPrint('🔓 Autologin emulatore: $emulatorAutologinEmail');
  } catch (e) {
    debugPrint('⚠️ Autologin emulatore fallito: $e');
  }
}

Future<void> _connectToEmulators() async {
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
  final firebaseOptions = isStaging
      ? StagingFirebaseOptions.currentPlatform
      : prod.DefaultFirebaseOptions.currentPlatform;

  // PRIMA di `Firebase.initializeApp`, non dopo: su web
  // `firebase_core_web.initializeApp` ATTENDE l'`ensurePluginInitialized` di
  // ogni servizio registrato, e quello di `firebase_auth_web` crea l'istanza JS
  // di Auth e poi fa `onWaitInitState()` — cioè aspetta il primo
  // `onAuthStateChanged`, quindi il ripristino completo della sessione salvata,
  // token incluso. A quel punto l'SDK ha già parlato con PRODUZIONE e ha messo
  // `_canInitEmulator` a false: il successivo `useAuthEmulator` fallisce con
  // `auth/emulator-config-failed`, che `firebase_auth_web` **ingoia in
  // silenzio**. L'app resta legata al progetto vero senza un solo errore.
  //
  // Il nome dell'app non si può leggere da `Firebase.app()` qui (non c'è ancora
  // un'app): è la costante `defaultFirebaseAppName`, la stessa che
  // `Firebase.initializeApp` usa quando `name` è omesso.
  if (useEmulator) {
    try {
      await clearFirebaseAuthPersistence(
        apiKey: firebaseOptions.apiKey,
        appName: defaultFirebaseAppName,
      );
    } catch (error, stackTrace) {
      // Fail-closed, ma non con una pagina bianca: questo caso è previsto
      // quando un'altra scheda tiene aperto IndexedDB e deve dire al tester
      // esattamente come recuperare senza inizializzare Firebase produzione.
      debugPrint('Avvio emulatore bloccato: $error');
      debugPrintStack(stackTrace: stackTrace);
      runApp(EmulatorStartupErrorApp(details: error.toString()));
      return;
    }
  }

  await Firebase.initializeApp(
    options: firebaseOptions,
  );

  if (useEmulator) {
    await _connectToEmulators();
    // Dopo aver agganciato l'emulatore, mai prima: sarebbe un uso di auth che
    // impedisce a `useAuthEmulator` di attaccarsi.
    await _autologin();
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

/// Schermata minimale e Firebase-free mostrata quando non si può garantire la
/// pulizia della sessione Auth prima dell'avvio in modalità emulatore.
class EmulatorStartupErrorApp extends StatelessWidget {
  final String details;

  const EmulatorStartupErrorApp({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gpp_bad_outlined,
                        size: 56, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Avvio emulatore bloccato',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chiudi le altre schede di Fit House e ricarica questa '
                      'pagina. L\'app non proseguirà finché non può escludere '
                      'una sessione Firebase di produzione.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      details,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
