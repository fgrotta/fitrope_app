import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/admin_dashboard_page.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

UserSubscription _sub(String planKey, DateTime end) => UserSubscription(
      planKey: planKey,
      family: planKey.startsWith('pt_')
          ? SubscriptionFamily.PT
          : SubscriptionFamily.OPEN,
      billingMode: BillingMode.ENTRIES,
      courseTypeTags: const {'Open'},
      remainingEntries: 10,
      startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
      endDate: Timestamp.fromDate(end),
    );

FitropeUser _user({
  List<UserSubscription> subscriptions = const [],
  int modelVersion = 2,
  TipologiaIscrizione? tipologia,
  Timestamp? fineIscrizione,
}) =>
    FitropeUser(
      uid: 'a',
      email: 'abbonato@test.it',
      name: 'Alba',
      lastName: 'Abbonata',
      role: 'User',
      courses: const [],
      createdAt: DateTime(2026, 1, 1),
      activeSubscriptions: subscriptions,
      subscriptionModelVersion: modelVersion,
      tipologiaIscrizione: tipologia,
      fineIscrizione: fineIscrizione,
    );

Future<void> _openDrawer(WidgetTester tester, FitropeUser user) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      endDrawer: UserListDrawer(title: 'Elenco', users: [user], onClose: () {}),
      body: const SizedBox(),
    ),
  ));
  tester.firstState<ScaffoldState>(find.byType(Scaffold)).openEndDrawer();
  await tester.pumpAndSettle();
}

/// Il testo c'è ed è visibile per intero (il bug era un'unica riga troncata
/// subito dopo "Scadenza abb.:").
void _expectFullyVisible(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  expect(
    tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
    isFalse,
    reason: '"$text" troncato',
  );
}

void main() {
  testWidgets('una riga per abbonamento, con tipologia e scadenza',
      (tester) async {
    final future = DateTime.now().add(const Duration(days: 60));
    final futureLabel = '${future.day.toString().padLeft(2, '0')}/'
        '${future.month.toString().padLeft(2, '0')}/${future.year}';
    await _openDrawer(
      tester,
      _user(subscriptions: [
        _sub('open_10i_3m', future),
        _sub('pt_10i_3m', future),
      ]),
    );

    _expectFullyVisible(tester, 'Open 10 ingressi · 3 mesi');
    _expectFullyVisible(tester, 'PT 10 ingressi · 3 mesi');
    expect(find.text('Scade il $futureLabel'), findsNWidgets(2));
  });

  testWidgets('abbonamento scaduto nello snapshot marcato come tale',
      (tester) async {
    await _openDrawer(
      tester,
      _user(subscriptions: [_sub('open_10i_1m', DateTime(2020, 3, 1))]),
    );

    _expectFullyVisible(tester, 'Open 10 ingressi · 1 mese');
    expect(find.text('Scaduto il 01/03/2020'), findsOneWidget);
  });

  testWidgets('documento senza versione ma con snapshot vivo', (tester) async {
    // Caso del seed emulatore (abbonato@test.it): prima il drawer leggeva la
    // fineIscrizione legacy, null, e mostrava "Scadenza abb.:" vuoto.
    await _openDrawer(
      tester,
      _user(
        modelVersion: 1,
        subscriptions: [
          _sub('open_10i_3m', DateTime.now().add(const Duration(days: 60))),
        ],
      ),
    );

    _expectFullyVisible(tester, 'Open 10 ingressi · 3 mesi');
    expect(find.textContaining('Scade il '), findsOneWidget);
  });

  testWidgets('titolo lungo va a capo invece di stare su una riga',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        endDrawer: UserListDrawer(
          title: 'In scadenza (30 gg) – Abbonamento trimestrale',
          users: [_user()],
          onClose: () {},
        ),
        body: const SizedBox(),
      ),
    ));
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openEndDrawer();
    await tester.pumpAndSettle();

    final title = find.text('In scadenza (30 gg) – Abbonamento trimestrale');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).height, greaterThan(16),
        reason: 'deve andare a capo');
  });

  testWidgets('senza abbonamenti: messaggio esplicito', (tester) async {
    await _openDrawer(tester, _user());

    expect(find.text('Nessun abbonamento attivo'), findsOneWidget);
  });

  testWidgets('legacy V1: tipologia e data di fine iscrizione', (tester) async {
    await _openDrawer(
      tester,
      _user(
        modelVersion: 1,
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        fineIscrizione: Timestamp.fromDate(DateTime(2020, 5, 10)),
      ),
    );

    _expectFullyVisible(tester, 'Abbonamento Mensile');
    expect(find.text('Scaduto il 10/05/2020'), findsOneWidget);
  });
}
