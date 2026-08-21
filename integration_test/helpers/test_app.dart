import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/firebase_bootstrap.dart';
import 'package:fitrope_app/firebase_options_staging.dart';
import 'package:fitrope_app/main.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

bool _firebaseReady = false;

/// Avvia l'app reale ([MyApp]) per un test E2E esclusivamente contro Emulator
/// Suite oppure staging. Una build senza target sicuro fallisce prima di
/// inizializzare Firebase e non può quindi toccare produzione.
///
/// Replica il minimo dell'init di `main.dart` SENZA OneSignal (che richiede il
/// browser/SDK e non serve ai test) e supera lo SplashScreen, che ha un delay
/// di 2s e uno spinner infinito (quindi non si può usare `pumpAndSettle` lì).
Future<void> launchTestApp(
  WidgetTester tester, {
  bool resetSession = true,
}) async {
  if (useEmulator == isStaging) {
    throw StateError(
      'Target E2E non sicuro: specificare esattamente uno tra '
      'USE_EMULATOR=true e APP_ENV=staging. Produzione è vietata.',
    );
  }
  if (isStaging) {
    final projectId = StagingFirebaseOptions.currentPlatform.projectId;
    if (!projectId.contains('staging') || projectId == 'fit-rope-app-1f575') {
      throw StateError(
        'Target E2E staging non sicuro: FIREBASE_PROJECT_ID="$projectId".',
      );
    }
  }

  if (!_firebaseReady) {
    await initializeApplicationServices(initializeNotifications: false);
    _firebaseReady = true;
  }
  store.dispatch(const ResetAppStateAction());
  invalidateCoursesCache();
  invalidateAllUserCaches();
  if (resetSession && FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.signOut().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'Timeout durante il reset della sessione Firebase Auth.',
          ),
        );
  }
  await tester.pumpWidget(
    StoreProvider(
      store: store,
      child: MyApp(key: UniqueKey()),
    ),
  );

  // SplashScreen: aspetta il redirect reale (Future.delayed di 2s).
  // Non usiamo pumpAndSettle: con il binding web anche le pagine successive
  // possono continuare a schedulare frame e impedire il settle indefinitamente.
  await tester.pump();
  // Avanza il clock del binding: una Future.delayed reale non è sufficiente
  // quando il timer della SplashScreen è governato dal clock dei widget test.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Pompa frame ripetutamente finché [finder] trova un widget o scade [timeout].
/// Utile dopo azioni che scatenano chiamate di rete reali (login, iscrizione),
/// che `pumpAndSettle` da solo non aspetta.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  throw StateError(
    'Timeout (${timeout.inSeconds}s): widget non trovato → $finder',
  );
}

/// Variante: aspetta che [finder] NON trovi più nulla (es. la pagina di login
/// sparisce dopo un login andato a buon fine).
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) return;
  }
  throw StateError(
    'Timeout (${timeout.inSeconds}s): widget ancora presente → $finder',
  );
}
