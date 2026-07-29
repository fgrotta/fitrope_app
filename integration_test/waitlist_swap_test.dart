import 'package:fitrope_app/types/course.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/seed.dart';
import 'helpers/test_app.dart';

/// Scenario E2E: lista d'attesa con "scambio" di posto su un corso da 1 posto.
///
///  1. Admin crea un corso con 1 solo posto (settimana di Ferragosto).
///  2. Utente 1 si iscrive.
///  3. Utente 2 non può iscriversi (corso pieno) → si mette in lista d'attesa.
///  4. Admin vede Utente 1 iscritto e Utente 2 in lista d'attesa.
///  5. Utente 1 si disiscrive.
///  6. Utente 2 (posto liberato) si iscrive e viene rimosso dalla lista d'attesa.
///  7. Admin vede Utente 2 iscritto e nessuno in lista d'attesa.
///
/// PRECONDIZIONE sui dati: sia TEST_USER1 sia TEST_USER2 devono avere un
/// abbonamento attivo con entrate disponibili (altrimenti non risultano
/// iscrivibili / non possono entrare in lista d'attesa).
///
/// `skip: true` finché non viene eseguito e validato il primo run verde.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    assertCredentials(adminTest);
    assertCredentials(trainerTest);
    assertCredentials(utenteBase1);
    assertCredentials(utenteBase2);
  });

  testWidgets(
    'Waitlist: scambio di posto tra Utente 1 e Utente 2 su un corso da 1 posto',
    (tester) async {
      Course? corso;

      // === 1. Admin crea il corso da 1 posto ============================
      await launchTestApp(tester);
      await login(tester, adminTest);
      final trainerId = await resolveUserIdByEmail(trainerTest.email);
      corso = await createFerragostoTestCourse(trainerId: trainerId, capacity: 1);
      addTearDown(() async {
        if (corso != null) await deleteTestCourse(corso.uid);
      });

      final uid = corso.uid;
      final nomeUtente1 = await resolveUserNameByEmail(utenteBase1.email);
      final nomeUtente2 = await resolveUserNameByEmail(utenteBase2.email);

      // === 2. Utente 1 si iscrive =======================================
      await logoutAndRestart(tester);
      await login(tester, utenteBase1);
      await openFerragostoCourses(tester);
      await expectCourseAction(tester, uid, 'Prenotati'); // CAN_SUBSCRIBE
      await tapCourseAction(tester, uid);
      await expectCourseAction(tester, uid, 'Rimuovi iscrizione'); // SUBSCRIBED

      // === 3. Utente 2 non può iscriversi → lista d'attesa ==============
      await logoutAndRestart(tester);
      await login(tester, utenteBase2);
      await openFerragostoCourses(tester);
      // Corso pieno → l'azione disponibile è la lista d'attesa.
      await expectCourseAction(tester, uid, 'Lista d\'attesa'); // CAN_WAITLIST
      await tapCourseAction(tester, uid);
      await confirmDialog(tester, 'Conferma'); // dialog lista d'attesa
      await expectCourseAction(tester, uid, 'Esci dalla lista d\'attesa'); // IN_WAITLIST

      // === 4. Admin: Utente 1 iscritto, Utente 2 in lista d'attesa ======
      await logoutAndRestart(tester);
      await login(tester, adminTest);
      await openFerragostoCourses(tester);
      await pumpUntilFound(
        tester,
        find.descendant(of: courseCard(uid), matching: find.textContaining('Iscritti (1/1)')),
      );
      expect(
        find.descendant(of: courseCard(uid), matching: find.textContaining(nomeUtente1)),
        findsWidgets,
        reason: 'Admin deve vedere Utente 1 tra gli iscritti',
      );
      expect(
        find.descendant(of: courseCard(uid), matching: find.textContaining('Lista d\'attesa (1)')),
        findsOneWidget,
        reason: 'Admin deve vedere 1 utente in lista d\'attesa',
      );
      expect(
        find.descendant(of: courseCard(uid), matching: find.textContaining(nomeUtente2)),
        findsWidgets,
        reason: 'Admin deve vedere Utente 2 in lista d\'attesa',
      );

      // === 5. Utente 1 si disiscrive ====================================
      await logoutAndRestart(tester);
      await login(tester, utenteBase1);
      await openFerragostoCourses(tester);
      await expectCourseAction(tester, uid, 'Rimuovi iscrizione');
      await tapCourseAction(tester, uid);
      // Corso mesi nel futuro → disiscrizione senza dialog di conferma.
      // Posto liberato e Utente 1 non più iscritto → può ri-prenotarsi.
      await expectCourseAction(tester, uid, 'Prenotati');

      // === 6. Utente 2 occupa il posto liberato =========================
      await logoutAndRestart(tester);
      await login(tester, utenteBase2);
      await openFerragostoCourses(tester);
      // In lista d'attesa + posto disponibile → può iscriversi ora.
      await expectCourseAction(tester, uid, 'Posto disponibile! Iscriviti ora'); // WAITLIST_SPOT_AVAILABLE
      await tapCourseAction(tester, uid);
      await expectCourseAction(tester, uid, 'Rimuovi iscrizione'); // SUBSCRIBED (rimosso da waitlist)

      // === 7. Admin: Utente 2 iscritto, nessuno in lista d'attesa =======
      await logoutAndRestart(tester);
      await login(tester, adminTest);
      await openFerragostoCourses(tester);
      await pumpUntilFound(
        tester,
        find.descendant(of: courseCard(uid), matching: find.textContaining(nomeUtente2)),
      );
      expect(
        find.descendant(of: courseCard(uid), matching: find.textContaining('Iscritti (1/1)')),
        findsOneWidget,
        reason: 'Admin deve vedere Utente 2 iscritto',
      );
      expect(
        find.descendant(of: courseCard(uid), matching: find.textContaining('Lista d\'attesa')),
        findsNothing,
        reason: 'La lista d\'attesa deve essere vuota (nessuna sezione mostrata)',
      );
    },
    skip: true,
  );
}
