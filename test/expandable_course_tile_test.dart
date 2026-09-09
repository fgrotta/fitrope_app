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
    VoidCallback? onCollapse,
    VoidCallback? onCardButton,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExpandableCourseTile(
          expanded: expanded,
          onCollapse: onCollapse,
          collapsed: GestureDetector(
            onTap: onTap ?? () {},
            child: const SizedBox(height: 64, child: Text('riga')),
          ),
          expandedChild: SizedBox(
            height: 210,
            child: Column(
              children: [
                const Text('card'),
                ElevatedButton(
                  onPressed: onCardButton ?? () {},
                  child: const Text('Prenotati'),
                ),
              ],
            ),
          ),
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
    // Si parte da chiusa e si apre: è il percorso vero. Montare già aperto
    // NON anima, per scelta (vedi il test dedicato più sotto).
    await pump(tester, expanded: false);
    await tester.pumpAndSettle();
    await pump(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cardScale(tester), closeTo(kCourseTileCardStartScale, 0.01));

    await tester.pump(const Duration(milliseconds: 160)); // metà di 320ms
    final meta = cardScale(tester);
    expect(meta, greaterThan(kCourseTileCardStartScale));
    expect(meta, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(cardScale(tester), closeTo(1.0, 0.001));
  });

  testWidgets('l\'opacità della card segue lo stesso avanzamento della scala',
      (tester) async {
    await pump(tester, expanded: false);
    await tester.pumpAndSettle();
    await pump(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cardOpacity(tester), closeTo(0.0, 0.02));
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

  group('chiusura al tocco sulla card', () {
    testWidgets('toccare la card aperta la richiude', (tester) async {
      // La riga che l'aveva aperta non c'è più: senza questo, la card resta
      // aperta e non c'è modo di tornare alla lista.
      var closed = 0;
      await pump(tester, expanded: true, onCollapse: () => closed++);
      await tester.pumpAndSettle();
      await tester.tap(find.text('card'));
      expect(closed, 1);
    });

    testWidgets('un pulsante dentro la card riceve il tocco, non la chiusura',
        (tester) async {
      // "Prenotati" deve prenotare: se la chiusura mangiasse il tocco, dalla
      // card aperta non si potrebbe più agire sul corso.
      var closed = 0, pressed = 0;
      await pump(
        tester,
        expanded: true,
        onCollapse: () => closed++,
        onCardButton: () => pressed++,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prenotati'));
      await tester.pump();
      expect(pressed, 1);
      expect(closed, 0);
    });

    testWidgets('chiusa, la card non è nell\'albero e non chiude nulla',
        (tester) async {
      var closed = 0;
      await pump(tester, expanded: false, onCollapse: () => closed++);
      await tester.pumpAndSettle();
      expect(find.text('card'), findsNothing);
      expect(closed, 0);
    });

    testWidgets('senza onCollapse la card resta semplicemente non toccabile',
        (tester) async {
      await pump(tester, expanded: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('card'));
      expect(tester.takeException(), isNull);
    });
  });

  group('chiusura: animazione inversa, piu\' rapida', () {
    test('la durata di chiusura e\' minore di quella di apertura', () {
      expect(kCourseTileCloseDuration, lessThan(kCourseTileAnimationDuration));
    });

    testWidgets('chiudendo la card rimpicciolisce invece di sparire di colpo',
        (tester) async {
      await pump(tester, expanded: true);
      await tester.pumpAndSettle();
      expect(cardScale(tester), closeTo(1.0, 0.001));

      await pump(tester, expanded: false);
      await tester.pump(const Duration(milliseconds: 1));
      // ancora nell'albero, e in ritirata verso la scala di partenza
      expect(find.text('card'), findsOneWidget);
      final s1 = cardScale(tester);
      expect(s1, lessThan(1.0));

      await tester.pump(kCourseTileCloseDuration ~/ 2);
      expect(cardScale(tester), lessThan(s1),
          reason: 'la scala deve continuare a scendere');

      await tester.pumpAndSettle();
    });

    testWidgets('chiudendo la card non viene tagliata all\'altezza della riga',
        (tester) async {
      await pump(tester, expanded: true);
      await tester.pumpAndSettle();

      await pump(tester, expanded: false);
      await tester.pump(const Duration(milliseconds: 1));

      final stack = tester.widget<Stack>(
        find.byKey(const Key('tile-transition-stack')),
      );
      expect(stack.clipBehavior, Clip.none);
      expect(
        tester.getSize(find.byType(ExpandableCourseTile)).height,
        greaterThan(tester
            .getSize(find.byKey(const Key('tile-transition-stack')))
            .height),
        reason: 'AnimatedSize conserva ancora spazio per la card in uscita',
      );
    });

    testWidgets('a chiusura conclusa la card non e\' piu\' nell\'albero',
        (tester) async {
      await pump(tester, expanded: true);
      await tester.pumpAndSettle();
      await pump(tester, expanded: false);
      await tester.pumpAndSettle();
      expect(find.text('card'), findsNothing);
      expect(find.text('riga'), findsOneWidget);
    });

    testWidgets('la chiusura si completa prima dell\'apertura', (tester) async {
      // Stessa finestra temporale: la chiusura e\' finita, l'apertura no.
      await pump(tester, expanded: true);
      await tester.pumpAndSettle();
      final apertaH = tester.getSize(find.byType(ExpandableCourseTile)).height;

      await pump(tester, expanded: false);
      await tester.pump(kCourseTileCloseDuration);
      await tester.pump(const Duration(milliseconds: 16));
      final dopoChiusura =
          tester.getSize(find.byType(ExpandableCourseTile)).height;
      expect(dopoChiusura, lessThan(apertaH));
      await tester.pumpAndSettle();
      final chiusaH = tester.getSize(find.byType(ExpandableCourseTile)).height;
      expect(dopoChiusura, closeTo(chiusaH, 1.0),
          reason: 'entro la durata di chiusura deve essere gia\' a regime');

      // l'apertura, nella stessa finestra, non e\' ancora finita
      await pump(tester, expanded: true);
      await tester.pump(kCourseTileCloseDuration);
      final aMetaApertura =
          tester.getSize(find.byType(ExpandableCourseTile)).height;
      expect(aMetaApertura, lessThan(apertaH));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('montata già aperta NON anima: sarebbe un rizoom a ogni rebuild',
      (tester) async {
    // La lista del calendario si ridisegna per molte ragioni (refresh degli
    // iscritti, cambio di stato del corso). Se il primo build animasse,
    // la riga aperta rifarebbe lo zoom ogni volta.
    await pump(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(cardScale(tester), closeTo(1.0, 0.001));
    expect(cardOpacity(tester), closeTo(1.0, 0.001));
  });
}
