import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/test_app.dart';

/// Percorsi UI distinti della matrice abbonamenti. Le fixture sono create dal
/// runner host con `prepare-enrollment-matrix`, quindi non condividono crediti
/// con seed o con un'altra run di CI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Esegue anche la validazione del namespace obbligatorio.
    for (final key in ['open', 'hyrox', 'pt', 'pack', 'trial', 'temporal']) {
      assertCredentials(matrixTestUser(key));
    }
  });

  testWidgets(
      'Matrice abbonamenti: consumo Open/pacchetto e stati attivi/scaduti',
      (tester) async {
    // Open 2x: una prenotazione già esiste, la prima azione usa l'ultimo slot
    // e la seconda card della stessa settimana passa a LIMIT.
    await launchTestApp(tester);
    await login(tester, matrixTestUser('open'));
    await openTestCourses(tester);
    await expectCourseAction(tester, matrixCourseId('open-first'), 'Prenotati');
    await tapCourseAction(tester, matrixCourseId('open-first'));
    await expectCourseAction(
      tester,
      matrixCourseId('open-second'),
      'Limite entrate settimanali raggiunto',
    );

    // Pacchetto legacy: 1 ingresso → prenotazione → esaurimento sul corso
    // successivo. La UI verifica il consumo effettivo della callable.
    await logoutAndRestart(tester);
    await login(tester, matrixTestUser('pack'));
    await openTestCourses(tester);
    await expectCourseAction(tester, matrixCourseId('pack-first'), 'Prenotati');
    await tapCourseAction(tester, matrixCourseId('pack-first'));
    await expectCourseAction(
      tester,
      matrixCourseId('pack-second'),
      'Entrate disponibili esaurite',
    );

    // Tutti i percorsi attivi non equivalenti restano prenotabili: due ENTRIES
    // del nuovo modello, prova a ingressi e legacy temporale a frequenza.
    for (final row in [
      (user: 'hyrox', course: 'hyrox-active'),
      (user: 'pt', course: 'pt-active'),
      (user: 'trial', course: 'trial-active'),
      (user: 'temporal', course: 'temporal-active'),
    ]) {
      await logoutAndRestart(tester);
      await login(tester, matrixTestUser(row.user));
      await openTestCourses(tester);
      await expectCourseAction(tester, matrixCourseId(row.course), 'Prenotati');
    }

    // Il target E2E copre ogni modello nella variante scaduta, non soltanto un
    // generic "abbonamento": il testo della card è il risultato del client
    // che ha letto snapshot/legacy e data del corso reali.
    for (final row in [
      (user: 'open-expired', course: 'open-expired'),
      (user: 'hyrox-expired', course: 'hyrox-expired'),
      (user: 'pt-expired', course: 'pt-expired'),
      (user: 'pack-expired', course: 'pack-expired'),
      (user: 'trial-expired', course: 'trial-expired'),
      (user: 'temporal-expired', course: 'temporal-expired'),
    ]) {
      await logoutAndRestart(tester);
      await login(tester, matrixTestUser(row.user));
      await openTestCourses(tester);
      await expectCourseAction(
        tester,
        matrixCourseId(row.course),
        'Abbonamento scaduto',
      );
    }
  });
}
