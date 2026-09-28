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
}
