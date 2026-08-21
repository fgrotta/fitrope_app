import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/seed.dart';
import 'helpers/test_app.dart';

Future<Map<String, dynamic>> _currentUserData() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Utente E2E non autenticato.');
  final snapshot =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final data = snapshot.data();
  if (data == null) throw StateError('Documento utente E2E mancante.');
  return data;
}

int _ptRemainingEntries(Map<String, dynamic> userData) {
  final subscriptions = userData['activeSubscriptions'] as List<dynamic>? ?? [];
  final pt = subscriptions.cast<Map<String, dynamic>>().firstWhere(
        (subscription) => subscription['family'] == 'PT',
        orElse: () => throw StateError('Subscription PT E2E mancante.'),
      );
  return (pt['remainingEntries'] as num).toInt();
}

/// Scenario E2E completo di iscrizione a un corso.
///
/// Flusso:
///   1. login Admin → crea un corso namespaced tra otto giorni, assegnato
///      al trainer indicato nel file utenti (default "Francesco Trainer");
///   2. logout → login utente base;
///   3. apre il Calendario e seleziona il giorno dinamico del corso;
///   4. tap "Prenotati" → verifica stato, ledger e consumo di un ingresso PT;
///   5. disiscrizione fuori finestra → verifica il rimborso dello stesso credito;
///   6. teardown: elimina il corso.
///
/// PRECONDIZIONE sui dati: l'utente base (TEST_USER1) deve avere un
/// abbonamento attivo con crediti/entrate disponibili, altrimenti il corso non
/// è in stato CAN_SUBSCRIBE e il test fallisce con un messaggio esplicito.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    assertCredentials(adminTest);
    assertCredentials(trainerTest);
    assertCredentials(utenteBase1);
  });

  testWidgets('Iscrizione: utente base si prenota al corso E2E dinamico', (
    tester,
  ) async {
    Course? corsoTest;

    // --- Setup: l'Admin crea il corso assegnandolo al trainer.
    await launchTestApp(tester);
    await login(tester, adminTest);
    final trainerId = await resolveUserIdByEmail(trainerTest.email);
    corsoTest = await createTestCourse(
      trainerId: trainerId,
      tipologia: 'Personal Trainer',
    );

    // Cleanup garantito anche in caso di fallimento.
    addTearDown(() async {
      if (corsoTest != null) {
        await deleteTestCourseAsAdmin(
          courseId: corsoTest.uid,
          adminEmail: adminTest.email,
          adminPassword: adminTest.password,
        );
      }
    });

    // --- L'utente base entra e apre il corso nel calendario.
    await logoutAndRestart(tester);
    await login(tester, utenteBase1);
    final entriesBefore = _ptRemainingEntries(await _currentUserData());
    await openCalendarTab(tester);
    await selectTestCourseDay(tester);

    final cardFinder = find.byKey(Key('course-card-${corsoTest.uid}'));
    final actionFinder = find.byKey(
      Key('course-action-button-${corsoTest.uid}'),
    );
    await pumpUntilFound(tester, actionFinder);

    // Precondizione: il corso deve essere iscrivibile (stato CAN_SUBSCRIBE →
    // testo "Prenotati"). Altrimenti l'utente di test non ha un abbonamento
    // valido con crediti.
    expect(
      find.descendant(of: cardFinder, matching: find.text('Prenotati')),
      findsOneWidget,
      reason: 'Il corso non è in stato "Prenotati": '
          'TEST_USER1 deve avere un abbonamento attivo con entrate disponibili.',
    );

    // --- Iscrizione.
    await tester.ensureVisible(actionFinder);
    await tester.tap(actionFinder);

    // L'iscrizione fa chiamate di rete reali: lo stato passa a SUBSCRIBED e il
    // bottone diventa "Rimuovi iscrizione".
    await pumpUntilFound(
      tester,
      find.descendant(
        of: cardFinder,
        matching: find.text('Rimuovi iscrizione'),
      ),
    );

    final afterSubscription = await _currentUserData();
    expect(afterSubscription['courses'], contains(corsoTest.uid));
    expect(_ptRemainingEntries(afterSubscription), entriesBefore - 1);
    expect(
      (afterSubscription['enrollmentConsumption'] as Map<String, dynamic>)
          .containsKey(corsoTest.uid),
      isTrue,
      reason: 'Il consumo deve registrare la subscription da rimborsare.',
    );

    // --- A9: oltre otto ore non serve conferma e l'ingresso viene rimborsato.
    await tester.tap(actionFinder);
    await pumpUntilFound(
      tester,
      find.descendant(of: cardFinder, matching: find.text('Prenotati')),
    );
    final afterRefund = await _currentUserData();
    expect(afterRefund['courses'], isNot(contains(corsoTest.uid)));
    expect(_ptRemainingEntries(afterRefund), entriesBefore);
    final consumptionAfterRefund =
        afterRefund['enrollmentConsumption'] as Map<String, dynamic>? ?? {};
    expect(consumptionAfterRefund.containsKey(corsoTest.uid), isFalse);
  });
}
