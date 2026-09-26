import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';

/// De-dup delle letture corsi: `Protected` e `HomePage` chiedono i corsi nello
/// stesso frame, e prima ognuno faceva la sua query. Due fetch distinte
/// producono due liste distinte: `identical` dice se la query è stata una sola.
void main() {
  group('getAllCourses (Firestore fake)', () {
    late FakeFirebaseFirestore db;

    Map<String, dynamic> courseDoc(String name) => {
          'name': name,
          'startDate':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
          'endDate': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 1, hours: 1))),
          'capacity': 10,
          'subscribed': 0,
        };

    setUp(() async {
      db = FakeFirebaseFirestore();
      invalidateCoursesCache();
      await db.collection('courses').doc('c1').set(courseDoc('Uno'));
    });

    test('due chiamate concorrenti condividono una sola lettura', () async {
      final a = getAllCourses(firestore: db);
      final b = getAllCourses(firestore: db);

      final results = await Future.wait([a, b]);

      expect(identical(results[0], results[1]), isTrue);
      expect(results[0].single.id, 'c1');
    });

    test('una richiesta forzata non riusa quella normale già in volo',
        () async {
      final normal = getAllCourses(firestore: db);
      final forced = getAllCourses(force: true, firestore: db);

      final results = await Future.wait([normal, forced]);

      expect(identical(results[0], results[1]), isFalse);
    });

    test('una richiesta normale si aggancia a quella forzata in volo',
        () async {
      final forced = getAllCourses(force: true, firestore: db);
      final normal = getAllCourses(firestore: db);

      final results = await Future.wait([forced, normal]);

      expect(identical(results[0], results[1]), isTrue);
    });

    test('invalidare durante il volo non lascia in cache dati vecchi',
        () async {
      final stale = getAllCourses(firestore: db);
      invalidateCoursesCache();
      await db.collection('courses').doc('c2').set(courseDoc('Due'));
      await stale;

      final fresh = await getAllCourses(firestore: db);

      expect(fresh.map((c) => c.id), containsAll(['c1', 'c2']));
    });
  });
}
