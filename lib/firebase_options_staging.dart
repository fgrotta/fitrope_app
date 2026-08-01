import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart" show kIsWeb;

/// Firebase Web configuration supplied by the staging deployment workflow.
/// Firebase API keys are identifiers, not secrets; values are injected with
/// --dart-define so this repository never contains staging project credentials.
class StagingFirebaseOptions {
  static const String _apiKey = String.fromEnvironment("FIREBASE_API_KEY");
  static const String _appId = String.fromEnvironment("FIREBASE_APP_ID");
  static const String _messagingSenderId =
      String.fromEnvironment("FIREBASE_MESSAGING_SENDER_ID");
  static const String _projectId =
      String.fromEnvironment("FIREBASE_PROJECT_ID");
  static const String _authDomain =
      String.fromEnvironment("FIREBASE_AUTH_DOMAIN");
  static const String _storageBucket =
      String.fromEnvironment("FIREBASE_STORAGE_BUCKET");
  static const String _measurementId =
      String.fromEnvironment("FIREBASE_MEASUREMENT_ID");

  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      throw UnsupportedError(
        "Staging Firebase is currently configured for the Web build only.",
      );
    }
    if (_apiKey.isEmpty ||
        _appId.isEmpty ||
        _messagingSenderId.isEmpty ||
        _projectId.isEmpty ||
        _authDomain.isEmpty) {
      throw StateError(
        "Missing staging Firebase configuration. Supply FIREBASE dart defines.",
      );
    }
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: _authDomain,
      storageBucket: _storageBucket,
      measurementId: _measurementId,
    );
  }
}
