import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/admin_users_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser listedUser(
  String uid,
  String name, {
  List<UserSubscription> subscriptions = const [],
}) =>
    FitropeUser(
      uid: uid,
      email: '$uid@example.com',
      name: name,
      lastName: 'Test',
      courses: const [],
      role: 'User',
      createdAt: DateTime(2026),
      activeSubscriptions: subscriptions,
    );

final _admin = FitropeUser(
  uid: 'admin',
  email: 'admin@example.com',
  name: 'Anna',
  lastName: 'Admin',
  courses: const [],
  role: 'Admin',
  createdAt: DateTime(2026),
);

Future<void> pumpUsers(WidgetTester tester, List<FitropeUser> users) async {
  await tester.binding.setSurfaceSize(const Size(1300, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  store.dispatch(SetUserAction(_admin));
  await tester.pumpWidget(
    StoreProvider(
      store: store,
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(1300, 900)),
            child: AdminUsersPage(loadUsersOperation: () async => users),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ricerca per nome o email aggiorna righe e conteggio',
      (tester) async {
    await pumpUsers(tester, [
      listedUser('mario', 'Mario'),
      listedUser('luisa', 'Luisa'),
    ]);
    expect(find.byKey(const ValueKey('admin-user-name-mario')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-user-name-luisa')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-users-search-field')),
      'luisa@example.com',
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('admin-user-name-mario')), findsNothing);
    expect(find.byKey(const ValueKey('admin-user-name-luisa')), findsOneWidget);
    expect(find.text('Utenti (1)'), findsOneWidget);
  });

  testWidgets('filtro scadenza include una multi-subscription', (tester) async {
    final now = DateTime.now();
    final expiring = UserSubscription(
      id: 'sub',
      planKey: 'open_3x_3m',
      family: SubscriptionFamily.OPEN,
      billingMode: BillingMode.FREQUENCY,
      courseTypeTags: const {'Open'},
      weeklyFrequency: 3,
      startDate: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      endDate: Timestamp.fromDate(now.add(const Duration(days: 10))),
    );
    await pumpUsers(tester, [
      listedUser('multi', 'Multi', subscriptions: [expiring]),
      listedUser('none', 'Nessuna'),
    ]);
    await tester.tap(find.byKey(const Key('admin-users-expiry-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In scadenza (prossimi 30 gg)').last);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const ValueKey('admin-user-name-multi')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-user-name-none')), findsNothing);
  });
}
