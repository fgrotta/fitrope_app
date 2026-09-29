import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/subscription_history_section.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserSubscription sub(String id, {DateTime? revokedAt, bool withId = true}) =>
    UserSubscription(
      id: withId ? id : null,
      planKey: 'open_2x_1m',
      family: SubscriptionFamily.OPEN,
      billingMode: BillingMode.FREQUENCY,
      courseTypeTags: {CourseTags.OPEN},
      weeklyFrequency: 2,
      startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
      endDate: Timestamp.fromDate(DateTime(2026, 2, 1)),
      revokedAt: revokedAt == null ? null : Timestamp.fromDate(revokedAt),
    );

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('storico Admin: azioni solo sui non revocati con id',
      (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [
        sub('live'),
        sub('revoked', revokedAt: DateTime(2026, 1, 10)),
        sub('snapshot', withId: false),
      ],
    )));
    expect(find.text('Modifica'), findsOneWidget);
    expect(find.text('Revoca'), findsOneWidget);
  });

  testWidgets('revocati nascosti finché non si tocca "Mostra tutti"',
      (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [
        sub('live'),
        sub('revoked', revokedAt: DateTime(2026, 1, 10)),
      ],
    )));
    expect(find.textContaining('Revocato il'), findsNothing);
    expect(find.text('Mostra tutti'), findsOneWidget);

    await tester.tap(find.text('Mostra tutti'));
    await tester.pump();
    expect(find.textContaining('Revocato il 10/01/2026'), findsOneWidget);
    expect(find.text('Nascondi revocati'), findsOneWidget);

    await tester.tap(find.text('Nascondi revocati'));
    await tester.pump();
    expect(find.textContaining('Revocato il'), findsNothing);
  });

  testWidgets('nessun revocato: niente CTA "Mostra tutti"', (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [sub('live')],
    )));
    expect(find.text('Mostra tutti'), findsNothing);
  });

  testWidgets('solo revocati: messaggio e CTA per vederli', (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [sub('revoked', revokedAt: DateTime(2026, 1, 10))],
    )));
    expect(find.text('Nessun abbonamento da mostrare'), findsOneWidget);
    await tester.tap(find.text('Mostra tutti'));
    await tester.pump();
    expect(find.textContaining('Revocato il'), findsOneWidget);
  });

  testWidgets('"Modifica" ha lo stesso colore di "Revoca"', (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [sub('live')],
      onEdit: (_) {},
      onRevoke: (_) {},
    )));
    Color? colorOf(String label) => tester
        .widget<RichText>(find
            .descendant(
              of: find.widgetWithText(TextButton, label),
              matching: find.byType(RichText),
            )
            .first)
        .text
        .style
        ?.color;
    expect(colorOf('Modifica'), colorOf('Revoca'));
  });

  testWidgets('snapshot (Trainer o storico non disponibile): nessuna azione',
      (tester) async {
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: false,
      subscriptions: [sub('live')],
    )));
    expect(find.text('Modifica'), findsNothing);
    expect(find.text('Revoca'), findsNothing);
    expect(SubscriptionHistorySection.titleFor(adminHistory: false),
        'Abbonamenti attivi');
    expect(
        SubscriptionHistorySection.titleFor(adminHistory: true), 'Abbonamenti');
  });

  testWidgets('elenco vuoto: testo per storico e per snapshot', (tester) async {
    await tester.pumpWidget(host(const SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [],
    )));
    expect(find.text('Nessun abbonamento'), findsOneWidget);
    await tester.pumpWidget(host(const SubscriptionHistorySection(
      adminHistory: false,
      subscriptions: [],
    )));
    expect(find.text('Nessun abbonamento attivo'), findsOneWidget);
  });

  testWidgets('i callback ricevono l\'abbonamento; busy li disattiva',
      (tester) async {
    UserSubscription? edited;
    UserSubscription? revoked;
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      subscriptions: [sub('live')],
      onEdit: (s) => edited = s,
      onRevoke: (s) => revoked = s,
    )));
    await tester.tap(find.text('Modifica'));
    await tester.tap(find.text('Revoca'));
    expect(edited?.id, 'live');
    expect(revoked?.id, 'live');

    edited = null;
    await tester.pumpWidget(host(SubscriptionHistorySection(
      adminHistory: true,
      busy: true,
      subscriptions: [sub('live')],
      onEdit: (s) => edited = s,
    )));
    await tester.tap(find.text('Modifica'));
    expect(edited, isNull);
  });

  testWidgets('conferma revoca: Annulla -> false, Revoca -> true',
      (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await confirmRevokeSubscription(context)),
            child: const Text('apri'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Le prenotazioni già fatte restano valide'),
        findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revoke-subscription-confirm')));
    await tester.pumpAndSettle();
    expect(results, [false, true]);
  });
}
