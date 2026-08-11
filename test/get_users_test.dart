import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/types/user_subscription.dart';

/// Test dell'API layer di getUsers/getUser con Firestore fake.
/// Copre il fix anti-regressione: la mappatura manuale che getUsers usava al
/// posto di FitropeUser.fromJson perdeva silenziosamente i campi aggiunti al
/// modello (activeSubscriptions, waitlistCourses, preferenze notifiche), quindi
/// la dashboard admin e la sezione "Abbonamenti attivi" restavano sempre vuote.
void main() {
  group('getUsers (Firestore fake)', () {
    late FakeFirebaseFirestore db;
    final start = Timestamp.fromDate(DateTime(2026, 1, 1));
    final end = Timestamp.fromDate(DateTime(2026, 12, 31));

    setUp(() {
      db = FakeFirebaseFirestore();
      // La cache è a livello di modulo: senza reset i test si sporcherebbero
      // a vicenda.
      invalidateUsersCache();
    });

    Map<String, dynamic> userDoc({
      String name = 'Mario',
      List<Map<String, dynamic>>? activeSubscriptions,
    }) =>
        {
          'email': 'mario@example.com',
          'name': name,
          'lastName': 'Rossi',
          'role': 'User',
          'courses': <String>['c1'],
          'waitlistCourses': <String>['c2'],
          'emailNotificationsEnabled': false,
          'pushNotificationsEnabled': false,
          'activeSubscriptions':
              activeSubscriptions ?? <Map<String, dynamic>>[],
          'createdAt': start,
        };

    test('preserva TUTTI i campi del modello, non solo quelli legacy',
        () async {
      await db.collection('users').doc('u1').set(userDoc(
            activeSubscriptions: [
              UserSubscription(
                id: 's1',
                planKey: 'open_2x',
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.FREQUENCY,
                courseTypeTags: const {'Open'},
                weeklyFrequency: 2,
                startDate: start,
                endDate: end,
              ).toJson(),
            ],
          ));

      final users = await getUsers(firestore: db);

      expect(users, hasLength(1));
      final u = users.first;
      // I campi che la mappatura manuale dimenticava.
      expect(u.activeSubscriptions, hasLength(1));
      expect(u.activeSubscriptions.first.planKey, 'open_2x');
      expect(u.activeSubscriptions.first.family, SubscriptionFamily.OPEN);
      expect(u.waitlistCourses, ['c2']);
      expect(u.emailNotificationsEnabled, isFalse);
      expect(u.pushNotificationsEnabled, isFalse);
      // I campi che invece funzionavano già.
      expect(u.uid, 'u1');
      expect(u.name, 'Mario');
      expect(u.courses, ['c1']);
    });

    test('uid viene dall\'id del documento, non dal campo salvato', () async {
      await db
          .collection('users')
          .doc('u1')
          .set({...userDoc(), 'uid': 'uid-stantio'});

      final users = await getUsers(firestore: db);

      expect(users.single.uid, 'u1');
    });

    test('un documento malformato viene saltato senza far cadere la lista',
        () async {
      await db.collection('users').doc('ok').set(userDoc());
      // createdAt non è un Timestamp: fromJson solleva su questo documento.
      await db
          .collection('users')
          .doc('rotto')
          .set({...userDoc(), 'createdAt': 'non-un-timestamp'});

      final users = await getUsers(firestore: db);

      expect(users.map((u) => u.uid), ['ok']);
    });

    test('un utente senza name/lastName resta nella lista con nome vuoto',
        () async {
      final doc = userDoc()
        ..remove('name')
        ..remove('lastName');
      await db.collection('users').doc('u1').set(doc);

      final users = await getUsers(firestore: db);

      expect(users.single.uid, 'u1');
      expect(users.single.name, '');
      expect(users.single.lastName, '');
    });

    test('getUser deserializza gli abbonamenti e ricava uid da snapshot.id',
        () async {
      await db.collection('users').doc('u1').set(userDoc(
            activeSubscriptions: [
              UserSubscription(
                planKey: 'pt_10',
                family: SubscriptionFamily.PT,
                billingMode: BillingMode.ENTRIES,
                courseTypeTags: const {'Personal Trainer'},
                remainingEntries: 10,
                startDate: start,
                endDate: end,
              ).toJson(),
            ],
          ));

      final user = await getUser('u1', firestore: db);

      expect(user, isNotNull);
      expect(user!.uid, 'u1');
      expect(user.activeSubscriptions.single.remainingEntries, 10);
    });

    test('getUser su documento inesistente ritorna null', () async {
      expect(await getUser('assente', firestore: db), isNull);
    });

    test('getTrainers filtra per ruolo e utenti attivi', () async {
      await db
          .collection('users')
          .doc('t1')
          .set({...userDoc(name: 'Trainer'), 'role': 'Trainer'});
      await db.collection('users').doc('t2').set(
          {...userDoc(name: 'Inattivo'), 'role': 'Trainer', 'isActive': false});
      await db.collection('users').doc('u1').set(userDoc());

      final trainers = await getTrainers(firestore: db);

      expect(trainers.map((u) => u.uid), ['t1']);
    });
  });
}
