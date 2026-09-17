import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/app_bootstrap.dart';
import 'package:fitrope_app/main.dart';
import 'package:fitrope_app/pages/welcome/welcome_page.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

bool _firebaseReady = false;

/// Avvia l'app reale ([MyApp]) per un test E2E, puntando all'ambiente di
/// ambiente selezionato dai dart-define (emulatore oppure staging).
///
/// Usa lo stesso bootstrap dell'app, ma senza OneSignal, e supera lo SplashScreen, che ha un delay
/// di 2s e uno spinner infinito (quindi non si può usare `pumpAndSettle` lì).
Future<void> launchTestApp(WidgetTester tester) async {
  if (!_firebaseReady) {
    await bootstrapApp(oneSignalAppId: '', enableOneSignal: false);
    // Le sessioni E2E vivono in una sola pagina Chrome: non devono essere
    // ripristinate da IndexedDB tra un avvio della suite e l'altro. La
    // persistenza NONE è supportata dal backend web e rende il reset
    // deterministico anche quando Chrome riusa un profilo temporaneo.
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    }
    _firebaseReady = true;
  }

  // Garantisce isolamento tra test: ogni avvio parte da stato loggato-fuori,
  // così lo Splash instrada sempre su Welcome (FirebaseAuth persiste la
  // sessione tra un test e l'altro nella stessa esecuzione).
  await FirebaseAuth.instance.signOut();
  // Sul web l'emulatore può propagare il cambio di sessione su
  // `currentUser` con un tick asincrono successivo al completamento di
  // `signOut()`. Aspettiamo che sia effettivamente nullo prima di montare lo
  // Splash, altrimenti può leggere ancora la sessione precedente e instradare
  // erroneamente su Protected.
  final authDeadline = DateTime.now().add(const Duration(seconds: 5));
  while (FirebaseAuth.instance.currentUser != null &&
      DateTime.now().isBefore(authDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  store.dispatch(SetUserAction(null));

  // MyApp usa un Navigator globale; una nuova key impedisce a pumpWidget di
  // riutilizzare la route protetta della sessione precedente.
  await tester
      .pumpWidget(StoreProvider(store: store, child: MyApp(key: UniqueKey())));

  // SplashScreen: aspetta il redirect reale (Future.delayed di 2s).
  // Non usiamo pumpAndSettle perché lo spinner anima all'infinito.
  await tester.pump();
  await Future<void>.delayed(const Duration(seconds: 3));
  // Dopo un logout il Navigator globale può conservare brevemente la route
  // protetta mentre il vecchio albero viene smontato. Con Auth già nullo,
  // reimpostiamo esplicitamente lo stack sulla Welcome: è lo stesso punto di
  // arrivo dello Splash, ma rende deterministico ogni nuovo scenario E2E.
  appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
    WELCOME_ROUTE,
    (_) => false,
  );
  await pumpUntilFound(tester, find.byType(WelcomePage));
  await tester.pumpAndSettle();
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
