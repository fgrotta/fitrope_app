import 'package:fitrope_app/layout/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageKey = Key('page');

Future<double> _pageWidth(
  WidgetTester tester, {
  required double screenWidth,
  required bool fullWidth,
}) async {
  tester.view.physicalSize = Size(screenWidth, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppShell(
      currentIndex: 2,
      isAdmin: true,
      onChangePage: (_) {},
      fullWidth: fullWidth,
      child: const SizedBox.expand(key: _pageKey),
    ),
  ));
  return tester.getSize(find.byKey(_pageKey)).width;
}

void main() {
  for (final screenWidth in [1440.0, 1920.0, 2560.0]) {
    testWidgets('fullWidth a $screenWidth px: tutto lo spazio dopo il rail',
        (tester) async {
      final width =
          await _pageWidth(tester, screenWidth: screenWidth, fullWidth: true);
      final rail = tester.getSize(find.byType(NavigationRail)).width;

      // Rail + VerticalDivider da 1 px.
      expect(width, screenWidth - rail - 1);
    });
  }

  testWidgets('senza fullWidth il contenuto resta limitato', (tester) async {
    expect(
      await _pageWidth(tester, screenWidth: 1440, fullWidth: false),
      1200,
    );
    expect(
      await _pageWidth(tester, screenWidth: 2560, fullWidth: false),
      1400,
    );
  });

  group('icona Guida', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool isAdmin,
      required double width,
      VoidCallback? onGuideTap,
    }) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppShell(
          currentIndex: 0,
          isAdmin: isAdmin,
          onChangePage: (_) {},
          onGuideTap: onGuideTap,
          child: const SizedBox.expand(),
        ),
      ));
    }

    testWidgets('c\'è nel rail per un Admin e apre la guida', (tester) async {
      var opened = 0;
      await pump(tester,
          isAdmin: true, width: 1280, onGuideTap: () => opened++);
      expect(find.byTooltip('Guida'), findsOneWidget);
      await tester.tap(find.byTooltip('Guida'));
      expect(opened, 1);
    });

    testWidgets('manca per chi non è Admin (User, Trainer, simulazione)',
        (tester) async {
      await pump(tester, isAdmin: false, width: 1280, onGuideTap: () {});
      expect(find.byTooltip('Guida'), findsNothing);
    });

    testWidgets('manca senza callback', (tester) async {
      await pump(tester, isAdmin: true, width: 1280);
      expect(find.byTooltip('Guida'), findsNothing);
    });
  });
}
