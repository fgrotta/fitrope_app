import 'package:fitrope_app/components/assign_subscription_card.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('assegna il piano selezionato e notifica il chiamante',
      (tester) async {
    String? capturedUser;
    String? capturedPlan;
    var assigned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignSubscriptionCard(
            userId: 'user-1',
            onAssigned: () => assigned = true,
            assignOperation: ({required userId, required planKey}) async {
              capturedUser = userId;
              capturedPlan = planKey;
            },
          ),
        ),
      ),
    );

    final dropdown = find.byKey(const Key('subscription-plan-dropdown'));
    final button = find.byKey(const Key('subscription-assign-button'));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(SubscriptionPlans.all.first.displayName).last);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(capturedUser, 'user-1');
    expect(capturedPlan, SubscriptionPlans.all.first.key);
    expect(assigned, isTrue);
    expect(find.text('Abbonamento assegnato'), findsOneWidget);
  });

  testWidgets('errore generico non invoca onAssigned', (tester) async {
    var assigned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignSubscriptionCard(
            userId: 'user-1',
            onAssigned: () => assigned = true,
            assignOperation: ({required userId, required planKey}) async {
              throw Exception('boom');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('subscription-plan-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SubscriptionPlans.all.first.displayName).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription-assign-button')));
    await tester.pumpAndSettle();
    expect(assigned, isFalse);
    expect(
      find.text("Errore durante l'assegnazione dell'abbonamento"),
      findsOneWidget,
    );
  });
}
