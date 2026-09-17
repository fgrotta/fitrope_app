import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/firebase_options.dart' as prod;
import 'package:fitrope_app/firebase_options_staging.dart';
import 'package:fitrope_app/services/onesignal_service.dart';
import 'package:fitrope_app/utils/clear_auth_persistence.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';

const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');
const String emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: 'localhost',
);
const int authEmulatorPort = int.fromEnvironment(
  'AUTH_EMULATOR_PORT',
  defaultValue: 9099,
);
const int firestoreEmulatorPort = int.fromEnvironment(
  'FIRESTORE_EMULATOR_PORT',
  defaultValue: 8080,
);
const int functionsEmulatorPort = int.fromEnvironment(
  'FUNCTIONS_EMULATOR_PORT',
  defaultValue: 5001,
);
const String emulatorProjectId = String.fromEnvironment(
  'EMULATOR_PROJECT_ID',
  defaultValue: 'demo-fitrope',
);
const String emulatorAutologinEmail = String.fromEnvironment(
  'EMULATOR_AUTOLOGIN_EMAIL',
);
const String emulatorAutologinPassword = String.fromEnvironment(
  'EMULATOR_AUTOLOGIN_PASSWORD',
);

/// Configura Firebase esattamente come l'app. I test E2E passano
/// [enableOneSignal: false], evitando side effect su device/browser.
Future<void> bootstrapApp({
  required String oneSignalAppId,
  bool enableOneSignal = true,
  bool clearEmulatorPersistence = true,
}) async {
  final firebaseOptions = useEmulator
      ? const FirebaseOptions(
          apiKey: 'emulator-api-key',
          appId: '1:000000000000:web:e2e',
          messagingSenderId: '000000000000',
          projectId: emulatorProjectId,
          authDomain: '$emulatorProjectId.firebaseapp.com',
        )
      : isStaging
          ? StagingFirebaseOptions.currentPlatform
          : prod.DefaultFirebaseOptions.currentPlatform;

  if (useEmulator && clearEmulatorPersistence) {
    await clearFirebaseAuthPersistence(
      apiKey: firebaseOptions.apiKey,
      appName: defaultFirebaseAppName,
    );
  }
  await Firebase.initializeApp(options: firebaseOptions);

  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      emulatorHost,
      firestoreEmulatorPort,
    );
    FirebaseFunctions.instanceFor(
      region: 'europe-west8',
    ).useFunctionsEmulator(emulatorHost, functionsEmulatorPort);
    if (emulatorAutologinEmail.isNotEmpty &&
        emulatorAutologinPassword.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emulatorAutologinEmail,
          password: emulatorAutologinPassword,
        );
      } catch (error) {
        debugPrint('Autologin emulatore fallito: $error');
      }
    }
  } else if (enableOneSignal) {
    OneSignalService.initialize(oneSignalAppId);
  }

  await initializeDateFormatting('it_IT', null);
}
