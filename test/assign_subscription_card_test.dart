import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/assign_subscription_card.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/subscription_widget_helpers.dart';

final today = DateTime(2026, 10, 15);

UserSubscription trial({DateTime? end, DateTime? revokedAt}) =>
    UserSubscription(
      id: 'trial',
      planKey: 'open_trial_1i_30d',
      family: SubscriptionFamily.OPEN,
      billingMode: BillingMode.ENTRIES,
      courseTypeTags: {CourseTags.OPEN},
      remainingEntries: 0,
      startDate: Timestamp.fromDate(DateTime(2026, 10, 1)),
      endDate: Timestamp.fromDate(end ?? DateTime(2026, 10, 31)),
      revokedAt: revokedAt == null ? null : Timestamp.fromDate(revokedAt),
    );

ElevatedButton assignButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Assegna'),
    );

void main() {
  testWidgets(
      'fine predefinita da piano + inizio, poi chiamata con orari di Roma',
      (tester) async {
    Map<String, Object?>? call;
    await tester.pumpWidget(
      hostWidget(
        AssignSubscriptionCard(
          userId: 'u1',
          today: today,
          assign: (
              {required userId, required planKey, startDate, endDate}) async {
            call = {'planKey': planKey, 'start': startDate, 'end': endDate};
            return (subscriptionId: 'new', replacedTrialIds: <String>[]);
          },
        ),
      ),
    );
    expect(find.text('15/10/2026'), findsOneWidget);
    expect(assignButton(tester).onPressed, isNull);

    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '3 mesi');
    expect(find.text('15/01/2027'), findsOneWidget);

    await tester.tap(find.text('Assegna'));
    await tester.pumpAndSettle();
    expect(call?['planKey'], 'open_2x_3m');
    final start = toItalianTime(call!['start'] as DateTime);
    final end = toItalianTime(call!['end'] as DateTime);
    expect([start.day, start.month, start.hour], [15, 10, 0]);
    expect([end.day, end.month, end.year, end.hour, end.minute],
        [15, 1, 2027, 23, 59]);
    expect(find.text('Abbonamento assegnato'), findsOneWidget);
  });

  testWidgets('una fine scelta a mano resta anche cambiando piano',
      (tester) async {
    await tester.pumpWidget(
      hostWidget(AssignSubscriptionCard(userId: 'u1', today: today)),
    );
    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '1 mese');
    expect(find.text('15/11/2026'), findsOneWidget);

    await pickDay(tester, const Key('assign-end-date'), 20);
    expect(find.text('20/11/2026'), findsOneWidget);

    await pickDropdown(tester, 'Durata', '6 mesi');
    expect(find.text('20/11/2026'), findsOneWidget);
  });

  testWidgets('fine prima dell\'inizio: messaggio e "Assegna" disattivato',
      (tester) async {
    await tester.pumpWidget(
      hostWidget(AssignSubscriptionCard(userId: 'u1', today: today)),
    );
    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '1 mese');
    await pickDay(tester, const Key('assign-end-date'), 10, monthShift: -1);
    expect(find.text('10/10/2026'), findsOneWidget);
    expect(
      find.text('La data di fine non può precedere la data di inizio'),
      findsOneWidget,
    );
    expect(assignButton(tester).onPressed, isNull);
  });

  testWidgets('avviso Prova solo per un Open con Prova non revocata',
      (tester) async {
    const warning = 'La Prova verrà chiusa e sostituita da questo abbonamento';
    await tester.pumpWidget(
      hostWidget(
        AssignSubscriptionCard(
            userId: 'u1', today: today, subscriptions: [trial()]),
      ),
    );
    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '1 mese');
    expect(find.text(warning), findsOneWidget);

    await selectPlan(tester, 'Personal Trainer', 'Pacchetto ingressi',
        '10 ingressi', '1 mese');
    expect(find.text(warning), findsNothing);

    await tester.pumpWidget(
      hostWidget(
        AssignSubscriptionCard(
          key: const ValueKey('revoked'),
          userId: 'u1',
          today: today,
          subscriptions: [trial(revokedAt: DateTime(2026, 10, 10))],
        ),
      ),
    );
    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '1 mese');
    expect(find.text(warning), findsNothing);
  });

  testWidgets('avviso anche per la Prova legacy e snackbar di sostituzione',
      (tester) async {
    await tester.pumpWidget(
      hostWidget(
        AssignSubscriptionCard(
          userId: 'u1',
          today: today,
          hasLegacyTrial: true,
          assign: (
                  {required userId,
                  required planKey,
                  startDate,
                  endDate}) async =>
              (subscriptionId: 'new', replacedTrialIds: <String>['trial']),
        ),
      ),
    );
    await selectPlan(
        tester, 'Open', 'Frequenza settimanale', '2 volte/settimana', '1 mese');
    expect(
      find.text('La Prova verrà chiusa e sostituita da questo abbonamento'),
      findsOneWidget,
    );
    await tester.tap(find.text('Assegna'));
    await tester.pumpAndSettle();
    expect(find.text('Abbonamento assegnato. Prova chiusa e sostituita'),
        findsOneWidget);
  });
}
