import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/intl_it.dart';
import 'package:fitrope_app/utils/italian_localizations.dart';

/// L'app usa solo l'italiano: al posto dei delegate `Global*Localizations`
/// (che portano in main.dart.js testi e date di ~80 lingue, ~300 KB) usa
/// delegate che costruiscono direttamente le classi italiane di
/// flutter_localizations.
void main() {
  setUpAll(initializeItalianDateFormatting);

  Future<BuildContext> pumpItalianApp(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: italianLocalizationsDelegates,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    return captured;
  }

  testWidgets('Material: testi e date in italiano', (tester) async {
    final context = await pumpItalianApp(tester);
    final l = MaterialLocalizations.of(context);

    expect(l.cancelButtonLabel, 'Annulla');
    expect(l.formatMediumDate(DateTime(2026, 9, 28)), 'lun 28 set');
    expect(l.formatMonthYear(DateTime(2026, 9, 28)), 'settembre 2026');
    expect(l.firstDayOfWeekIndex, 1); // lunedì
  });

  testWidgets('Cupertino e Widgets: italiano, sinistra→destra', (tester) async {
    final context = await pumpItalianApp(tester);

    expect(CupertinoLocalizations.of(context).todayLabel, 'Oggi');
    expect(Directionality.of(context), TextDirection.ltr);
  });

  testWidgets('il date picker mostra mese e giorni in italiano',
      (tester) async {
    final context = await pumpItalianApp(tester);
    showDatePicker(
      context: context,
      initialDate: DateTime(2026, 9, 28),
      firstDate: DateTime(2026),
      lastDate: DateTime(2027),
    );
    await tester.pumpAndSettle();

    expect(find.text('settembre 2026'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
  });

  test('in lib/ nessuno usa i delegate Global*Localizations', () {
    final global =
        RegExp(r'Global(Material|Cupertino|Widgets)Localizations\.delegate');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (global.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Riporterebbero in main.dart.js le traduzioni di tutte le '
            'lingue: usa italianLocalizationsDelegates.');
  });
}
