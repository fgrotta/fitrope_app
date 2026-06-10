import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/api/courses/updateCourse.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Copre il percorso EDIT (updateCourse), simmetrico a createCourse_test.
/// In modifica, CourseManagementPage usa courseToEdit.copyWith(...): qui si
/// verifica che i campi non modificati siano preservati (no regressione del
/// bug "campo perso nella copia manuale") e che la sala possa essere azzerata.
void main() {
  group('updateCourse (Firestore fake)', () {
    late FakeFirebaseFirestore db;
    final start = Timestamp.fromDate(DateTime(2026, 1, 1, 10));
    final end = Timestamp.fromDate(DateTime(2026, 1, 1, 11));

    Future<Course> seed() async {
      final created = await createCourse(
        Course(
          id: '',
          uid: '',
          name: 'Originale',
          startDate: start,
          endDate: end,
          capacity: 8,
          subscribed: 3,
          trainerId: 't1',
          tags: const ['Hyrox'],
          reminderEnabled: false,
          waitlistEnabled: false,
          sala: Sale.SALA_1,
        ),
        firestore: db,
      );
      return created!;
    }

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('edit che cambia solo il nome preserva tutti gli altri campi',
        () async {
      final created = await seed();

      // Come fa la pagina in modalità edit: copyWith su courseToEdit.
      await updateCourse(created.copyWith(name: 'Modificato'), firestore: db);

      final data =
          (await db.collection('courses').doc(created.uid).get()).data()!;
      expect(data['name'], 'Modificato');
      // Campi non editati: devono restare invariati.
      expect(data['reminderEnabled'], false);
      expect(data['waitlistEnabled'], false);
      expect(data['sala'], Sale.SALA_1);
      expect(data['trainerId'], 't1');
      expect(data['tags'], ['Hyrox']);
      expect(data['subscribed'], 3);
    });

    test('edit può azzerare la sala (copyWith sala: null)', () async {
      final created = await seed();

      await updateCourse(created.copyWith(sala: null), firestore: db);

      final data =
          (await db.collection('courses').doc(created.uid).get()).data()!;
      expect(data['sala'], isNull);
      // Gli altri restano.
      expect(data['reminderEnabled'], false);
      expect(data['trainerId'], 't1');
    });

    test('NON riscrive i campi server-owned subscribed/waitlist (modello stale)',
        () async {
      final created = await seed();

      // Il server (callable enrollment) nel frattempo ha aggiornato i campi.
      await db.collection('courses').doc(created.uid).update({
        'subscribed': 7,
        'waitlist': ['u9'],
      });

      // L'admin salva una modifica corso partendo dal modello in memoria
      // (stale: subscribed=3, waitlist=[]) — non deve riportarli indietro.
      await updateCourse(created.copyWith(name: 'Rinominato'), firestore: db);

      final data =
          (await db.collection('courses').doc(created.uid).get()).data()!;
      expect(data['name'], 'Rinominato');
      expect(data['subscribed'], 7);
      expect(data['waitlist'], ['u9']);
    });
  });
}
