import 'package:fitrope_app/components/subscription_plan_picker.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/subscription_widget_helpers.dart';

void main() {
  testWidgets('initialPlanKey preseleziona tutta la cascata', (tester) async {
    await tester.pumpWidget(
      hostWidget(
        SubscriptionPlanPicker(initialPlanKey: 'open_3x_6m', onChanged: (_) {}),
      ),
    );
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Frequenza settimanale'), findsOneWidget);
    expect(find.text('3 volte/settimana'), findsOneWidget);
    expect(find.text('6 mesi'), findsOneWidget);
  });

  testWidgets('Prova come piano iniziale: solo la famiglia, nessun piano',
      (tester) async {
    await tester.pumpWidget(
      hostWidget(
        SubscriptionPlanPicker(
          initialPlanKey: SubscriptionPlans.trial.key,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Frequenza settimanale'), findsNothing);
    expect(find.text('Pacchetto ingressi'), findsNothing);
  });

  testWidgets(
      'la cascata completa notifica il piano; la Prova non è tra le opzioni',
      (tester) async {
    SubscriptionPlan? last;
    await tester.pumpWidget(
      hostWidget(SubscriptionPlanPicker(onChanged: (plan) => last = plan)),
    );
    await pickDropdown(tester, 'Tipo', 'Open');
    await pickDropdown(tester, 'Modalita', 'Pacchetto ingressi');
    // Tra le varianti a ingressi c'è solo il pacchetto: la Prova (1 ingresso) no.
    await tester.tap(find.ancestor(
      of: find.text('Variante'),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 ingressi'), findsNothing);
    await tester.tap(find.text('10 ingressi').last);
    await tester.pumpAndSettle();
    await pickDropdown(tester, 'Durata', '1 mese');
    expect(last?.key, 'open_10i_1m');

    await pickDropdown(tester, 'Tipo', 'Personal Trainer');
    expect(last, isNull);
  });
}
