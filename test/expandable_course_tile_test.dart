import 'package:fitrope_app/components/expandable_course_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// La tile non conosce Course né Firestore: riceve i due stati già costruiti.
  /// Così si testa l'animazione senza tirarsi dietro mezzo dominio.
  Future<void> pump(
    WidgetTester tester, {
    required bool expanded,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExpandableCourseTile(
          expanded: expanded,
          collapsed: GestureDetector(
            onTap: onTap ?? () {},
            child: const SizedBox(height: 64, child: Text('riga')),
          ),
          expandedChild: const SizedBox(height: 210, child: Text('card')),
        ),
      ),
    ));
  }

  double cardOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.byKey(const Key('tile-card-opacity')))
      .opacity;

  /// Si legge `entry(0,0)`, non `getMaxScaleOnAxis()`: `Transform.scale`
  /// costruisce `Matrix4.diagonal3Values(s, s, 1)` e il massimo fra gli assi è
  /// sempre l'1 della Z, quindi quel metodo restituirebbe 1.0 a ogni frame e il
  /// test passerebbe anche con l'animazione ferma.
  double cardScale(WidgetTester tester) => tester
      .widget<Transform>(find.descendant(
          of: find.byKey(const Key('tile-card-opacity')),
          matching: find.byType(Transform)))
      .transform
      .entry(0, 0);

  testWidgets('chiusa: c\'è la riga e non la card', (tester) async {
    await pump(tester, expanded: false);
    await tester.pumpAndSettle();
    expect(find.text('riga'), findsOneWidget);
    expect(find.text('card'), findsNothing);
  });

  testWidgets('aperta: c\'è la card e non la riga', (tester) async {
    await pump(tester, expanded: true);
    await tester.pumpAndSettle();
    expect(find.text('card'), findsOneWidget);
    expect(find.text('riga'), findsNothing);
  });

  testWidgets('l\'altezza cresce aprendo e torna chiudendo', (tester) async {
    await pump(tester, expanded: false);
    await tester.pumpAndSettle();
    final chiusa = tester.getSize(find.byType(ExpandableCourseTile)).height;

    await pump(tester, expanded: true);
    await tester.pumpAndSettle();
    final aperta = tester.getSize(find.byType(ExpandableCourseTile)).height;

    expect(aperta, greaterThan(chiusa));

    await pump(tester, expanded: false);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ExpandableCourseTile)).height, chiusa);
  });

  testWidgets('A2: lo zoom parte rimpicciolito e arriva a scala piena',
      (tester) async {
    // Questo test ha già preso un bug vero: scambiando lo slot dei due layer
    // in uno Stack, il layer entrante veniva ricostruito e la scala nasceva
    // già a 1 — l'animazione non partiva affatto.
    await pump(tester, expanded: true);
    await tester.pump(); // primo frame: il tween è al valore iniziale
    expect(cardScale(tester), closeTo(kCourseTileCardStartScale, 0.001));

    await tester.pump(const Duration(milliseconds: 160)); // metà di 320ms
    final meta = cardScale(tester);
    expect(meta, greaterThan(kCourseTileCardStartScale));
    expect(meta, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(cardScale(tester), closeTo(1.0, 0.001));
  });

  testWidgets('l\'opacità della card segue lo stesso avanzamento della scala',
      (tester) async {
    await pump(tester, expanded: true);
    await tester.pump();
    expect(cardOpacity(tester), closeTo(0.0, 0.01));
    await tester.pumpAndSettle();
    expect(cardOpacity(tester), closeTo(1.0, 0.001));
  });

  testWidgets('la riga chiusa resta toccabile', (tester) async {
    var tapped = 0;
    await pump(tester, expanded: false, onTap: () => tapped++);
    await tester.pumpAndSettle();
    await tester.tap(find.text('riga'));
    expect(tapped, 1);
  });

  testWidgets('aperta, la riga non è più nell\'albero né toccabile',
      (tester) async {
    var tapped = 0;
    await pump(tester, expanded: true, onTap: () => tapped++);
    await tester.pumpAndSettle();
    expect(find.text('riga'), findsNothing);
    expect(tapped, 0);
  });
}
