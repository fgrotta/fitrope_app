import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/admin_dashboard_page.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser dashboardUser(DateTime now) => FitropeUser(
      uid: 'multi',
      email: 'multi@example.com',
      name: 'Multi',
      lastName: 'Sub',
      courses: const [],
      role: 'User',
      createdAt: now.subtract(const Duration(days: 2)),
      activeSubscriptions: [
        UserSubscription(
          id: 'sub',
          planKey: 'open_3x_3m',
          family: SubscriptionFamily.OPEN,
          billingMode: BillingMode.FREQUENCY,
          courseTypeTags: const {'Open'},
          weeklyFrequency: 3,
          startDate: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          endDate: Timestamp.fromDate(now.add(const Duration(days: 10))),
        ),
      ],
    );

void main() {
  testWidgets('dashboard mostra il guard sui breakpoint non desktop',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 700)),
          child: AdminDashboardPage(
            onOpenUserList: (_, __) {},
            loadUsers: () async => [],
            loadCourses: () async => [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dashboard disponibile solo su desktop'), findsOneWidget);
  });

  testWidgets('KPI desktop include una scadenza multi-subscription',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 900)),
          child: AdminDashboardPage(
            onOpenUserList: (_, __) {},
            loadUsers: () async => [dashboardUser(now)],
            loadCourses: () async => [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = find.text('In scadenza (prossimi 30 gg)');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final metric = find.byKey(
      const Key('dashboard-metric-in-scadenza-prossimi-30-gg'),
    );
    expect(metric, findsOneWidget);
    expect(
        find.descendant(of: metric, matching: find.text('1')), findsOneWidget);
  });
}
