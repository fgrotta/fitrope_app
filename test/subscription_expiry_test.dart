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
}
