import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/firebase_options.dart' as prod;
import 'package:fitrope_app/firebase_options_staging.dart';
import 'package:fitrope_app/services/onesignal_service.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';

const String oneSignalAppId = '154fc17b-3ef8-4421-a1e6-466172fa48db';

/// Ambiente di test locale (Firebase Emulator Suite).
const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');
const String emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: 'localhost',
);

bool _emulatorsConnected = false;
bool _localeInitialized = false;

FirebaseOptions get _selectedFirebaseOptions => isStaging
    ? StagingFirebaseOptions.currentPlatform
    : prod.DefaultFirebaseOptions.currentPlatform;

Future<void> _connectToEmulators() async {
  if (_emulatorsConnected) return;
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  FirebaseFunctions.instanceFor(
    region: 'europe-west8',
  ).useFunctionsEmulator(emulatorHost, 5001);
  _emulatorsConnected = true;
  debugPrint(
    '⚠️ EMULATORE FIREBASE ATTIVO ($emulatorHost) — nessun dato reale',
  );
}

/// Inizializzazione condivisa tra l'entry point reale e il runner E2E.
///
/// [initializeNotifications] deve restare false nei test: evita di associare le
/// fixture all'app OneSignal reale anche quando il backend selezionato è staging.
Future<void> initializeApplicationServices({
  bool initializeNotifications = true,
}) async {
  final notificationsEnabled =
      initializeNotifications && !useEmulator && !isStaging;
  OneSignalService.setEnabled(notificationsEnabled);
  final options = _selectedFirebaseOptions;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  } else if (Firebase.app().options.projectId != options.projectId) {
    throw StateError(
      'Firebase era già inizializzato per "${Firebase.app().options.projectId}", '
      'ma l\'ambiente selezionato richiede "${options.projectId}".',
    );
  }

  if (useEmulator) {
    await _connectToEmulators();
  } else if (notificationsEnabled) {
    // Staging non ha una app OneSignal separata: non associare browser e
    // fixture all'app di produzione. Le email server-side restano allowlisted.
    OneSignalService.initialize(oneSignalAppId);
  }

  if (!_localeInitialized) {
    await initializeDateFormatting('it_IT', null);
    initItalianTime();
    _localeInitialized = true;
  }
}
