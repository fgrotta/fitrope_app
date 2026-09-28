import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget hostWidget(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Apre il dropdown con etichetta [label] e sceglie la voce [item].
Future<void> pickDropdown(
    WidgetTester tester, String label, String item) async {
  await tester.tap(find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> selectPlan(
  WidgetTester tester,
  String family,
  String mode,
  String variant,
  String duration,
) async {
  await pickDropdown(tester, 'Tipo', family);
  await pickDropdown(tester, 'Modalita', mode);
  await pickDropdown(tester, 'Variante', variant);
  await pickDropdown(tester, 'Durata', duration);
}

/// Apre il date picker del bottone [buttonKey], si sposta di [monthShift]
/// mesi (negativo = indietro) e sceglie il giorno [day].
Future<void> pickDay(
  WidgetTester tester,
  Key buttonKey,
  int day, {
  int monthShift = 0,
}) async {
  await tester.tap(find.byKey(buttonKey));
  await tester.pumpAndSettle();
  for (var i = 0; i < monthShift.abs(); i++) {
    await tester.tap(
      find.byTooltip(monthShift < 0 ? 'Previous month' : 'Next month'),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('$day'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
