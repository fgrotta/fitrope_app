import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/accept_regolamento.dart';
import 'package:fitrope_app/api/authentication/toggle_user_status.dart';
import 'package:fitrope_app/api/authentication/update_user.dart';
import 'package:fitrope_app/api/courses/create_course.dart';
import 'package:fitrope_app/api/courses/update_course.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Layer B — la rete di sicurezza nel layer API.
///
/// Il valore di questi test sta nell'asserzione sul **dato**: non basta che la
/// funzione lanci, il documento deve restare byte per byte quello di prima. Il
/// server autorizzerebbe davvero queste scritture (`request.auth.uid` è
/// l'admin), quindi il blocco client-side è l'unica difesa.
void main() {
  final admin = simUser(uid: 'admin-1', role: 'Admin');
  final target = simUser(uid: 'user-1', role: 'User');

  tearDown(SimulationSession.stop);

  final start = Timestamp.fromDate(DateTime(2026, 1, 1, 10));
  final end = Timestamp.fromDate(DateTime(2026, 1, 1, 11));

  Course sample({String uid = '', String name = 'Originale'}) => Course(
        id: uid,
        uid: uid,
        name: name,
        startDate: start,
        endDate: end,
        capacity: 8,
        subscribed: 3,
        tags: const ['Open'],
      );

  group('scritture sui corsi', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    test('updateCourse lancia e il documento resta identico', () async {
      final created = (await createCourse(sample(), firestore: db))!;
      final prima =
          (await db.collection('courses').doc(created.uid).get()).data();

      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        updateCourse(created.copyWith(name: 'Modificato', capacity: 99),
            firestore: db),
        throwsA(isA<SimulationBlockedException>()),
      );

      final dopo =
          (await db.collection('courses').doc(created.uid).get()).data();
      expect(dopo, prima);
      expect(dopo!['name'], 'Originale');
    });

    test('createCourse lancia e nessun documento viene creato', () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        createCourse(sample(name: 'Nuovo'), firestore: db),
        throwsA(isA<SimulationBlockedException>()),
      );

      final snapshot = await db.collection('courses').get();
      expect(snapshot.docs, isEmpty);
    });
  });

  // updateUser / toggleUserStatus / acceptRegolamento non accettano
  // un'istanza Firestore iniettabile: la garanzia è che la guardia sia la PRIMA
  // riga, quindi lanciano prima di toccare `FirebaseFirestore.instance` (che in
  // un test senza Firebase inizializzato darebbe un errore diverso — ed è
  // proprio questa distinzione a provare che non è stata raggiunta).
  group('scritture sull\'utente (guardia prima di qualsiasi I/O)', () {
    test('updateUser lancia SimulationBlockedException', () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        updateUser(
          original: target,
          name: 'Nuovo',
          lastName: 'Nome',
          role: 'User',
        ),
        throwsA(isA<SimulationBlockedException>()),
      );
    });

    test('toggleUserStatus lancia SimulationBlockedException', () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        toggleUserStatus(target.uid, false),
        throwsA(isA<SimulationBlockedException>()),
      );
    });

    test('acceptRegolamento lancia SimulationBlockedException', () async {
      SimulationSession.start(admin: admin, target: target);

      await expectLater(
        acceptRegolamento(target.uid),
        throwsA(isA<SimulationBlockedException>()),
      );
    });
  });

  test('a simulazione spenta le stesse scritture passano', () async {
    final db = FakeFirebaseFirestore();

    final created = await createCourse(sample(name: 'Vivo'), firestore: db);

    expect(created, isNotNull);
    expect((await db.collection('courses').get()).docs, hasLength(1));
  });

  test('il messaggio mostrato all\'utente è la sola frase italiana', () {
    expect(const SimulationBlockedException('updateUser').toString(),
        'Modalità simulazione: azione non eseguita.');
  });
}
