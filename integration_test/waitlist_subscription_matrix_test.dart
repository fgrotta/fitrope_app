import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_users.dart';
import 'helpers/actions.dart';
import 'helpers/test_app.dart';

Future<Map<String, dynamic>> _currentUserData() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('La fixture E2E non risulta autenticata.');
  final snapshot =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return snapshot.data() ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> _courseData(String key) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('courses')
      .doc(matrixCourseId(key))
      .get();
  return snapshot.data() ?? <String, dynamic>{};
}

/// Stati waitlist che non hanno un percorso di consumo: join attivo e tre
/// rifiuti di eligibility. I controlli Firestore dopo l'azione sono intenzionali
/// e verificano l'invariante a due lati (corso + utente), non solo il testo UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    for (final key in [
      'waitlist',
      'open-expired',
      'open-limit',
      'pack-exhausted'
    ]) {
      assertCredentials(matrixTestUser(key));
    }
  });

  testWidgets('Matrice waitlist: join senza consumo e rifiuti senza scritture',
      (tester) async {
    await launchTestApp(tester);
    await login(tester, matrixTestUser('waitlist'));
    await openTestCourses(tester);
    final before = await _currentUserData();
    await expectCourseAction(
        tester, matrixCourseId('waitlist-active'), 'Lista d\'attesa');
    await tapCourseAction(tester, matrixCourseId('waitlist-active'));
    await confirmDialog(tester, 'Conferma');
    await expectCourseAction(
      tester,
      matrixCourseId('waitlist-active'),
      'Esci dalla lista d\'attesa',
    );

    final joinedUser = await _currentUserData();
    final joinedCourse = await _courseData('waitlist-active');
    expect(joinedUser['waitlistCourses'],
        contains(matrixCourseId('waitlist-active')));
    expect(joinedCourse['waitlist'],
        contains(FirebaseAuth.instance.currentUser!.uid));
    expect(
      joinedUser['activeSubscriptions'],
      before['activeSubscriptions'],
      reason: 'Il join waitlist non deve consumare o modificare lo snapshot.',
    );

    for (final row in [
      (
        user: 'open-expired',
        course: 'open-expired',
        label: 'Abbonamento scaduto',
      ),
      (
        user: 'open-limit',
        course: 'open-limit-full',
        label: 'Limite entrate settimanali raggiunto',
      ),
      (
        user: 'pack-exhausted',
        course: 'pack-exhausted-full',
        label: 'Entrate disponibili esaurite',
      ),
    ]) {
      await logoutAndRestart(tester);
      await login(tester, matrixTestUser(row.user));
      await openTestCourses(tester);
      await expectCourseAction(tester, matrixCourseId(row.course), row.label);

      final user = await _currentUserData();
      final course = await _courseData(row.course);
      expect(user['waitlistCourses'] ?? [],
          isNot(contains(matrixCourseId(row.course))));
      expect(course['waitlist'] ?? [], isEmpty);
    }
  });
}
