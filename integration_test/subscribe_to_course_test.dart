import 'package:fitrope_app/types/course.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/seed.dart';
import 'helpers/test_app.dart';

/// Scenario E2E completo di iscrizione a un corso.
///
/// Flusso:
///   1. login Admin → crea il corso "Test" (settimana di Ferragosto) assegnato
///      al trainer indicato nel file utenti (default "Francesco Trainer");
///   2. logout → login utente base;
///   3. apre il Calendario, va a Ferragosto, trova la card del corso;
///   4. tap "Prenotati" → verifica che lo stato passi a iscritto;
///   5. teardown: elimina il corso (rimuove anche l'iscrizione).
///
/// PRECONDIZIONE sui dati: l'utente base (TEST_USER1) deve avere un
/// abbonamento attivo con crediti/entrate disponibili, altrimenti il corso non
/// è in stato CAN_SUBSCRIBE e il test fallisce con un messaggio esplicito.
///
/// `skip: true` finché non viene eseguito e validato il primo run verde
/// (richiede Chrome + credenziali reali in test_env.json). Per abilitarlo,
/// rimuovi `skip: true`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    assertCredentials(adminTest);
    assertCredentials(trainerTest);
    assertCredentials(utenteBase1);
  });

  testWidgets(
    'Iscrizione: utente base si prenota al corso "Test" di Ferragosto',
    (tester) async {
      Course? corsoTest;

      // --- Setup: l'Admin crea il corso assegnandolo al trainer.
      await launchTestApp(tester);
      await login(tester, adminTest);
      final trainerId = await resolveUserIdByEmail(trainerTest.email);
      corsoTest = await createFerragostoTestCourse(trainerId: trainerId);

      // Cleanup garantito anche in caso di fallimento.
      addTearDown(() async {
        if (corsoTest != null) {
          await deleteTestCourse(corsoTest.uid);
        }
      });

      // --- L'utente base entra e apre il corso nel calendario.
      await logoutAndRestart(tester);
      await login(tester, utenteBase1);
      await openCalendarTab(tester);
      await selectFerragosto(tester);

      final cardFinder = find.byKey(Key('course-card-${corsoTest.uid}'));
      final actionFinder =
          find.byKey(Key('course-action-button-${corsoTest.uid}'));
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
        find.descendant(of: cardFinder, matching: find.text('Rimuovi iscrizione')),
      );
    },
    skip: true,
  );
}
