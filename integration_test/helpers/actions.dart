import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/pages/protected/protected.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/test_users.dart';
import 'seed.dart';
import 'test_app.dart';

/// Esegue il login completo partendo dalla WelcomePage:
/// tap su "Entra" → compila email/password → tap "Login" → attende il redirect
/// alla pagina protetta (LoginPage sparisce).
Future<void> login(WidgetTester tester, TestUser user) async {
  debugPrint('[E2E login] apro form ${user.email}');
  // WelcomePage → LoginPage
  await tester.tap(find.text('Entra'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  await tester.enterText(
    find.byKey(const Key('login-email-field')),
    user.email,
  );
  await tester.enterText(
    find.byKey(const Key('login-password-field')),
    user.password,
  );
  await tester.pump(const Duration(milliseconds: 200));

  debugPrint('[E2E login] invio credenziali ${user.email}');
  await tester.tap(find.byKey(const Key('login-submit-button')));

  // Il login fa chiamate di rete reali (Auth + Firestore) e poi naviga con
  // pushNamed(PROTECTED_ROUTE): la LoginPage resta nello stack sotto, quindi
  // aspettiamo che compaia la pagina protetta. Se invece compare un errore a
  // schermo, falliamo subito riportandolo.
  final protected = find.byType(Protected);
  final errori = <Finder>[
    find.textContaining('Email o password'),
    find.textContaining('non verificata'),
    find.textContaining('disattivato'),
  ];

  const timeout = Duration(seconds: 25);
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (protected.evaluate().isNotEmpty) {
      debugPrint('[E2E login] completato ${user.email}');
      return;
    }
    for (final err in errori) {
      if (err.evaluate().isNotEmpty) {
        final msg = (err.evaluate().first.widget as Text).data;
        throw StateError('Login fallito per ${user.email}: "$msg"');
      }
    }
  }
  throw StateError(
    'Login: pagina protetta non comparsa entro ${timeout.inSeconds}s per ${user.email}',
  );
}

/// Esegue il logout (stessa `signOut` usata dalla UI) e riavvia l'app, così
/// si riparte dalla WelcomePage. Indipendente dal breakpoint (non dipende da
/// dove è posizionato il bottone di logout).
Future<void> logoutAndRestart(WidgetTester tester) async {
  // Smonta prima l'area protetta mantenendo ancora valida la sessione corrente.
  // Le dashboard avviano diverse letture Firestore in background: effettuare
  // subito signOut le farebbe terminare senza auth e le rules risponderebbero
  // permission-denied, contaminando il caso E2E successivo.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await Future<void>.delayed(const Duration(seconds: 1));

  // Cambio utente tecnico tra scenari: non passa da OneSignal. Il logout UI
  // viene verificato separatamente nei test di sessione.
  await FirebaseAuth.instance.signOut();
  await launchTestApp(tester, resetSession: false);
}

/// Apre la tab "Calendario" della pagina protetta.
Future<void> openCalendarTab(WidgetTester tester) async {
  await tester.tap(find.text('Calendario').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Naviga il calendario fino al giorno dello slot E2E dinamico.
Future<void> selectTestCourseDay(WidgetTester tester) async {
  final target = toItalianTime(testCourseSlot().start);
  final now = toItalianTime(DateTime.now());
  final monthsForward =
      (target.year - now.year) * 12 + (target.month - now.month);

  for (var i = 0; i < monthsForward; i++) {
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(milliseconds: 500));
  }

  await tester.tap(find.text('${target.day}').first);
  await tester.pump(const Duration(milliseconds: 500));
}

// ---------------------------------------------------------------------------
// Helper sulle card dei corsi (identificate per uid via Key)
// ---------------------------------------------------------------------------

/// Finder della card di un corso.
Finder courseCard(String uid) => find.byKey(Key('course-card-$uid'));

/// Finder del bottone di azione (Prenotati / Rimuovi iscrizione / Lista
/// d'attesa / Posto disponibile…) di un corso.
Finder courseActionButton(String uid) =>
    find.byKey(Key('course-action-button-$uid'));

/// Attende che il bottone di azione del corso [uid] mostri il testo [label]
/// (cioè che il corso sia nello stato atteso). Fallisce con messaggio chiaro.
Future<void> expectCourseAction(
  WidgetTester tester,
  String uid,
  String label,
) async {
  await pumpUntilFound(
    tester,
    find.descendant(of: courseCard(uid), matching: find.text(label)),
  );
}

/// Tappa il bottone di azione del corso [uid] (assicurandosi sia visibile).
Future<void> tapCourseAction(WidgetTester tester, String uid) async {
  final f = courseActionButton(uid);
  await pumpUntilFound(tester, f);
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Conferma un dialog tappando il pulsante con testo [label] (es. "Conferma").
Future<void> confirmDialog(WidgetTester tester, String label) async {
  await pumpUntilFound(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Vai al Calendario e seleziona la giornata dello slot E2E.
Future<void> openTestCourses(WidgetTester tester) async {
  await openCalendarTab(tester);
  await selectTestCourseDay(tester);
}
