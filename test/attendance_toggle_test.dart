import 'package:fitrope_app/components/attendance_toggle.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceRecord _rec(bool present, AttendanceSource source) =>
    AttendanceRecord(
      courseId: 'c1',
      userId: 'u1',
      courseStartMillis: 0,
      present: present,
      source: source,
    );

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

void main() {
  testWidgets('senza record: non selezionato; il tocco chiede presente',
      (tester) async {
    bool? asked;
    await _pump(
      tester,
      AttendanceToggle(record: null, onChanged: (v) => asked = v),
    );
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.selected, isFalse);
    await tester.tap(find.text('Presente'));
    expect(asked, isTrue);
  });

  testWidgets('presente: selezionato; il tocco chiede assente', (tester) async {
    bool? asked;
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(true, AttendanceSource.trainer),
        onChanged: (v) => asked = v,
      ),
    );
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
    await tester.tap(find.text('Presente'));
    expect(asked, isFalse);
    expect(find.text('dichiarata dal socio'), findsNothing);
  });

  testWidgets('pending: spinner e tocco disabilitato', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      AttendanceToggle(record: null, pending: true, onChanged: (_) => calls++),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).onSelected, isNull);
    await tester.tap(find.text('Presente'));
    expect(calls, 0);
  });

  testWidgets('check-in del socio: sotto-etichetta "dichiarata dal socio"',
      (tester) async {
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(true, AttendanceSource.self),
        onChanged: (_) {},
      ),
    );
    expect(find.text('dichiarata dal socio'), findsOneWidget);
  });

  testWidgets('area di tocco almeno 48 px', (tester) async {
    await _pump(tester, AttendanceToggle(record: null, onChanged: (_) {}));
    final size = tester.getSize(find.byType(FilterChip));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
