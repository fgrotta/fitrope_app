import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/dashboard_subscription_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser user({
  required String uid,
  Timestamp? legacyEnd,
  List<UserSubscription> subscriptions = const [],
  String role = 'User',
  bool active = true,
}) {
  return FitropeUser(
    uid: uid,
    email: '$uid@example.com',
    name: 'Test',
    lastName: uid,
    courses: const [],
    fineIscrizione: legacyEnd,
    role: role,
    isActive: active,
    createdAt: DateTime(2026),
    activeSubscriptions: subscriptions,
  );
}

UserSubscription subscription(String id, DateTime end) => UserSubscription(
      id: id,
      planKey: 'open_3x_3m',
      family: SubscriptionFamily.OPEN,
      billingMode: BillingMode.FREQUENCY,
      courseTypeTags: const {'Open'},
      weeklyFrequency: 3,
      startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
      endDate: Timestamp.fromDate(end),
    );

void main() {
  final now = DateTime(2026, 8, 20, 12);

  test('KPI scadenze include legacy e multi-sub senza duplicare utenti', () {
    final legacy = user(
      uid: 'legacy',
      legacyEnd: Timestamp.fromDate(now.add(const Duration(days: 10))),
    );
    final multi = user(
      uid: 'multi',
      subscriptions: [
        subscription('a', now.add(const Duration(days: 5))),
        subscription('b', now.add(const Duration(days: 20))),
      ],
    );
    final expired = user(
      uid: 'expired',
      subscriptions: [subscription('c', now.subtract(const Duration(days: 1)))],
    );

    expect(
      usersWithSubscriptionsExpiringWithin(
        [legacy, multi, expired],
        now: now,
      ).map((value) => value.uid),
      ['legacy', 'multi'],
    );
  });

  test('senza data esclude staff e utenti con snapshot multi-sub', () {
    final missing = user(uid: 'missing');
    final multi = user(
      uid: 'multi',
      subscriptions: [subscription('a', now.add(const Duration(days: 10)))],
    );
    final admin = user(uid: 'admin', role: 'Admin');

    expect(
      usersWithoutSubscriptionEndDate([missing, multi, admin])
          .map((value) => value.uid),
      ['missing'],
    );
  });
}
