import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/firebase_options.dart';
import 'package:fitrope_app/main.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

bool _firebaseReady = false;

/// Avvia l'app reale ([MyApp]) per un test E2E, puntando all'ambiente di
/// PRODUZIONE (stesse opzioni di [DefaultFirebaseOptions]).
///
/// Replica il minimo dell'init di `main.dart` SENZA OneSignal (che richiede il
/// browser/SDK e non serve ai test) e supera lo SplashScreen, che ha un delay
/// di 2s e uno spinner infinito (quindi non si può usare `pumpAndSettle` lì).
Future<void> launchTestApp(WidgetTester tester) async {
  if (!_firebaseReady) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await initializeDateFormatting('it_IT', null);
    _firebaseReady = true;
  }

  // Garantisce isolamento tra test: ogni avvio parte da stato loggato-fuori,
  // così lo Splash instrada sempre su Welcome (FirebaseAuth persiste la
  // sessione tra un test e l'altro nella stessa esecuzione).
  await FirebaseAuth.instance.signOut();

  await tester.pumpWidget(
    StoreProvider(store: store, child: const MyApp()),
  );

  // SplashScreen: aspetta il redirect reale (Future.delayed di 2s).
  // Non usiamo pumpAndSettle perché lo spinner anima all'infinito.
  await tester.pump();
  await Future<void>.delayed(const Duration(seconds: 3));
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
