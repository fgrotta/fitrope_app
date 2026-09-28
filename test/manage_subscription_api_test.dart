import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/api/subscriptions/manage_subscription.dart';
import 'package:fitrope_app/components/active_subscription_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> doc(String userId, {Timestamp? revokedAt}) => {
      'userId': userId,
      'planKey': 'open_2x_1m',
      'family': 'OPEN',
      'billingMode': 'FREQUENCY',
      'courseTypeTags': ['Open'],
      'weeklyFrequency': 2,
      'remainingEntries': null,
      'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'endDate': Timestamp.fromDate(DateTime(2026, 2, 1)),
      if (revokedAt != null) 'revokedAt': revokedAt,
    };

void main() {
  test('getUserSubscriptions: tutti i documenti dell\'utente, con id e revoca',
      () async {
    final db = FakeFirebaseFirestore();
    final revokedAt = Timestamp.fromDate(DateTime(2026, 1, 10));
    await db.collection('subscriptions').doc('a').set(doc('u1'));
    await db
        .collection('subscriptions')
        .doc('b')
        .set(doc('u1', revokedAt: revokedAt));
    await db.collection('subscriptions').doc('c').set(doc('u2'));

    final subs = await getUserSubscriptions('u1', firestore: db);
    expect(subs.map((s) => s.id).toSet(), {'a', 'b'});
    expect(subs.firstWhere((s) => s.id == 'b').revokedAt, revokedAt);
  });

  testWidgets('ActiveSubscriptionCard: azioni visibili, revocato attenuato',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('subscriptions').doc('a').set(doc('u1'));
    await db.collection('subscriptions').doc('b').set(
          doc('u1', revokedAt: Timestamp.fromDate(DateTime(2026, 1, 10))),
        );
    final subs = await getUserSubscriptions('u1', firestore: db);
    final live = subs.firstWhere((s) => s.id == 'a');
    final revoked = subs.firstWhere((s) => s.id == 'b');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ActiveSubscriptionCard(
                subscription: live,
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Modifica'))
                ],
              ),
              ActiveSubscriptionCard(subscription: revoked),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Modifica'), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.textContaining('Revocato il 10/01/2026'), findsOneWidget);
  });
}
