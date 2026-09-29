import 'package:fitrope_app/components/edit_subscription_dialog.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/subscription_dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/subscription_widget_helpers.dart';

UserSubscription sub({
  String planKey = 'open_10i_3m',
  BillingMode billingMode = BillingMode.ENTRIES,
  int? weeklyFrequency,
  int? remainingEntries = 4,
}) =>
    UserSubscription(
      id: 's1',
      planKey: planKey,
      family: SubscriptionFamily.OPEN,
      billingMode: billingMode,
      courseTypeTags: {CourseTags.OPEN},
      weeklyFrequency: weeklyFrequency,
      remainingEntries: remainingEntries,
      startDate: subscriptionStartTimestamp(DateTime(2026, 10, 1)),
      endDate: subscriptionEndTimestamp(DateTime(2027, 1, 1)),
    );

Future<void> openDialog(
  WidgetTester tester,
  UserSubscription s, {
  UpdateSubscriptionFn? save,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  EditSubscriptionDialog(subscription: s, save: save),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
}

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const Key('edit-subscription-save')),
    );

Finder entriesField() => find.byKey(const Key('edit-remaining-entries'));

void main() {
  testWidgets('parte dal piano e dai valori attuali', (tester) async {
    await openDialog(tester, sub());
    expect(find.text('10 ingressi'), findsOneWidget);
    expect(find.text('3 mesi'), findsOneWidget);
    expect(find.text('01/10/2026'), findsOneWidget);
    expect(find.text('01/01/2027'), findsOneWidget);
    expect(tester.widget<TextField>(entriesField()).controller!.text, '4');
  });

  testWidgets('ingressi senza tetto: oltre il pacchetto va bene, vuoto no',
      (tester) async {
    await openDialog(tester, sub());
    await tester.enterText(entriesField(), '25');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.enterText(entriesField(), '');
    await tester.pump();
    expect(find.text('Indica gli ingressi residui'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('fine prima dell\'inizio: errore in linea', (tester) async {
    await openDialog(tester, sub());
    await pickDay(tester, const Key('edit-start-date'), 10, monthShift: 4);
    expect(find.text('10/02/2027'), findsOneWidget);
    expect(
      find.text('La data di fine non può precedere la data di inizio'),
      findsOneWidget,
    );
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets(
      'cambio tipologia: ricalcola fine e ingressi; FREQUENCY nasconde gli ingressi',
      (tester) async {
    await openDialog(
      tester,
      sub(
        planKey: 'open_2x_3m',
        billingMode: BillingMode.FREQUENCY,
        weeklyFrequency: 2,
        remainingEntries: null,
      ),
    );
    expect(entriesField(), findsNothing);

    await pickDropdown(tester, 'Modalita', 'Pacchetto ingressi');
    await pickDropdown(tester, 'Variante', '10 ingressi');
    await pickDropdown(tester, 'Durata', '6 mesi');
    expect(find.text('01/04/2027'), findsOneWidget);
    expect(tester.widget<TextField>(entriesField()).controller!.text, '10');

    await pickDropdown(tester, 'Modalita', 'Frequenza settimanale');
    expect(entriesField(), findsNothing);
  });

  testWidgets('modifiche manuali preservate al cambio tipologia',
      (tester) async {
    await openDialog(tester, sub());
    await tester.enterText(entriesField(), '7');
    await pickDay(tester, const Key('edit-end-date'), 20);
    expect(find.text('20/01/2027'), findsOneWidget);

    await pickDropdown(tester, 'Durata', '12 mesi');
    expect(find.text('20/01/2027'), findsOneWidget);
    expect(tester.widget<TextField>(entriesField()).controller!.text, '7');
  });

  testWidgets(
      'Prova: nessun piano preselezionato, Salva disattivato finché non si sceglie',
      (tester) async {
    await openDialog(
      tester,
      sub(planKey: 'open_trial_1i_30d', remainingEntries: 1),
    );
    expect(find.text('Seleziona la tipologia'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets(
      'salvataggio: invia piano, date di Roma e ingressi; chiude con true',
      (tester) async {
    Map<String, Object?>? call;
    await openDialog(
      tester,
      sub(),
      save: ({
        required subscriptionId,
        required planKey,
        required startDate,
        required endDate,
        remainingEntries,
        expectedRemainingEntries,
      }) async {
        call = {
          'expected': expectedRemainingEntries,
          'id': subscriptionId,
          'planKey': planKey,
          'start': startDate,
          'end': endDate,
          'remaining': remainingEntries,
        };
      },
    );
    await tester.enterText(entriesField(), '6');
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-subscription-save')));
    await tester.pumpAndSettle();
    expect(call?['id'], 's1');
    expect(call?['planKey'], 'open_10i_3m');
    expect(call?['remaining'], 6);
    expect(call?['expected'], 4);
    expect(
      call?['start'],
      subscriptionStartTimestamp(DateTime(2026, 10, 1)).toDate(),
    );
    expect(
        call?['end'], subscriptionEndTimestamp(DateTime(2027, 1, 1)).toDate());
    expect(find.byType(EditSubscriptionDialog), findsNothing);
  });
}
