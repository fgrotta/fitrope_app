import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_expiry.dart';

FitropeUser makeUser({
  required DateTime now,
  List<UserSubscription> subscriptions = const [],
  int modelVersion = 2,
  Timestamp? legacyEndDate,
}) {
  return FitropeUser(
    uid: 'u1',
    email: 'u1@example.com',
    name: 'Test',
    lastName: 'User',
    role: 'User',
    courses: const [],
    createdAt: now,
    activeSubscriptions: subscriptions,
    subscriptionModelVersion: modelVersion,
    fineIscrizione: legacyEndDate,
  );
}

UserSubscription subscription(String planKey, DateTime endDate) {
  return UserSubscription(
    id: planKey,
    planKey: planKey,
    family: SubscriptionFamily.OPEN,
    billingMode: BillingMode.ENTRIES,
    courseTypeTags: const {'Open'},
    remainingEntries: 3,
    startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
    endDate: Timestamp.fromDate(endDate),
  );
}

void main() {
  test('conta ogni piano V2 nella finestra di 30 giorni', () {
    final now = DateTime(2026, 9, 22);
    final user = makeUser(
      now: now,
      subscriptions: [
        subscription('open_10i_1m', now.add(const Duration(days: 10))),
        subscription('open_10i_3m', now.add(const Duration(days: 31))),
      ],
    );

    expect(
      subscriptionsExpiringInNext30Days(user, now: now),
      hasLength(1),
    );
    expect(countSubscriptionsExpiringInNext30Days([user], now: now), 1);
    expect(hasSubscriptionExpiringInNext30Days(user, now: now), isTrue);
  });

  test('V2 senza snapshot significa nessun abbonamento attivo', () {
    final user = makeUser(now: DateTime(2026, 9, 22));
    expect(hasNoActiveSubscription(user), isTrue);
  });

  test('V1 usa ancora la data legacy durante il rollout', () {
    final now = DateTime(2026, 9, 22);
    final user = makeUser(
      now: now,
      modelVersion: 1,
      legacyEndDate: Timestamp.fromDate(now.add(const Duration(days: 5))),
    );
    expect(hasSubscriptionExpiringInNext30Days(user, now: now), isTrue);
    expect(hasNoActiveSubscription(user), isFalse);
  });

  group('hasLiveSubscription', () {
    final now = DateTime(2026, 9, 22);

    test('V2 con un abbonamento non scaduto', () {
      final user = makeUser(now: now, subscriptions: [
        subscription('open_10i_1m', now.subtract(const Duration(days: 3))),
        subscription('open_10i_3m', now.add(const Duration(days: 3))),
      ]);
      expect(hasLiveSubscription(user, now: now), isTrue);
      expect(hasNoActiveSubscription(user, now: now), isFalse);
    });

    test('V2 con soli abbonamenti scaduti nello snapshot', () {
      final user = makeUser(now: now, subscriptions: [
        subscription('open_10i_1m', now.subtract(const Duration(days: 1))),
      ]);
      expect(hasLiveSubscription(user, now: now), isFalse);
      expect(hasNoActiveSubscription(user, now: now), isTrue);
    });

    test('scadenza oggi: ancora vivo, come liveSubscriptions', () {
      final user = makeUser(now: now, subscriptions: [
        subscription('open_10i_1m', now),
      ]);
      expect(hasLiveSubscription(user, now: now), isTrue);
    });

    test('documento V1 con snapshot vivo: vale il modello nuovo', () {
      // Come getCourseState: senza subscriptionModelVersion ma con abbonamenti
      // vivi, la fineIscrizione (qui null) non va letta.
      final user = makeUser(now: now, modelVersion: 1, subscriptions: [
        subscription('open_10i_3m', now.add(const Duration(days: 60))),
      ]);
      expect(hasLiveSubscription(user, now: now), isTrue);
      final expiries = subscriptionExpiries(user, now: now);
      expect(expiries, hasLength(1));
      expect(expiries.single.legacy, isFalse);
      expect(expiries.single.label, 'Open 10 ingressi · 3 mesi');
    });

    test('documento V1 con snapshot solo scaduto: torna alla data legacy', () {
      final user = makeUser(
        now: now,
        modelVersion: 1,
        legacyEndDate: Timestamp.fromDate(now.add(const Duration(days: 5))),
        subscriptions: [
          subscription('open_10i_1m', now.subtract(const Duration(days: 1))),
        ],
      );
      expect(hasLiveSubscription(user, now: now), isTrue);
      expect(subscriptionExpiries(user, now: now).single.legacy, isTrue);
    });

    test('V1: conta la data legacy', () {
      Timestamp at(int days) =>
          Timestamp.fromDate(now.add(Duration(days: days)));
      expect(
          hasLiveSubscription(
              makeUser(now: now, modelVersion: 1, legacyEndDate: at(5)),
              now: now),
          isTrue);
      expect(
          hasLiveSubscription(
              makeUser(now: now, modelVersion: 1, legacyEndDate: at(-1)),
              now: now),
          isFalse);
      expect(hasLiveSubscription(makeUser(now: now, modelVersion: 1), now: now),
          isFalse);
    });
  });
}
