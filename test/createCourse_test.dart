import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Test dell'API layer di createCourse con Firestore fake.
/// Copre il fix anti-regressione: createCourse NON deve perdere campi del corso
/// (in passato scartava reminderEnabled/waitlistEnabled, e avrebbe scartato sala).
void main() {
  group('createCourse (Firestore fake)', () {
    late FakeFirebaseFirestore db;
    final start = Timestamp.fromDate(DateTime(2026, 1, 1, 10));
    final end = Timestamp.fromDate(DateTime(2026, 1, 1, 11));

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('genera un uid e preserva TUTTI i campi del corso', () async {
      final input = Course(
        id: '',
        uid: '',
        name: 'Hyrox Mattina',
        startDate: start,
        endDate: end,
        capacity: 8,
        subscribed: 0,
        trainerId: 't1',
        tags: const ['Hyrox'],
        reminderEnabled: false,
        waitlistEnabled: false,
        sala: Sale.SALA_1,
      );

      final created = await createCourse(input, firestore: db);

      expect(created, isNotNull);
      expect(created!.uid, isNotEmpty);

      final snap = await db.collection('courses').doc(created.uid).get();
      expect(snap.exists, true);
      final data = snap.data()!;

      // Campi che la vecchia implementazione perdeva (forzati ai default true):
      expect(data['reminderEnabled'], false);
      expect(data['waitlistEnabled'], false);
      // Campo nuovo della PR1:
      expect(data['sala'], Sale.SALA_1);
      // Resto dei campi:
      expect(data['name'], 'Hyrox Mattina');
      expect(data['capacity'], 8);
      expect(data['subscribed'], 0);
      expect(data['trainerId'], 't1');
      expect(data['tags'], ['Hyrox']);
      expect(data['uid'], created.uid);
      expect(data['id'], created.uid);
    });

    test('una sala null resta null (corso senza sala)', () async {
      final created = await createCourse(
        Course(
          id: '',
          uid: '',
          name: 'Open',
          startDate: start,
          endDate: end,
          capacity: 6,
          subscribed: 0,
        ),
        firestore: db,
      );

      final data =
          (await db.collection('courses').doc(created!.uid).get()).data()!;
      expect(data['sala'], isNull);
    });

    test('non sovrascrive un corso con uid già presente', () async {
      // Pre-popola un documento esistente con dati noti.
      await db
          .collection('courses')
          .doc('existing')
          .set({'uid': 'existing', 'name': 'Originale'});

      final result = await createCourse(
        Course(
          id: 'existing',
          uid: 'existing',
          name: 'Nuovo Nome',
          startDate: start,
          endDate: end,
          capacity: 5,
          subscribed: 0,
        ),
        firestore: db,
      );

      expect(result, isNull);
      // Il doc preesistente NON deve essere stato toccato (early-return, non sovrascrittura).
      final snap = await db.collection('courses').doc('existing').get();
      expect(snap.data()!['name'], 'Originale');
      // Nessun documento aggiuntivo creato.
      expect((await db.collection('courses').get()).docs.length, 1);
    });
  });
}
