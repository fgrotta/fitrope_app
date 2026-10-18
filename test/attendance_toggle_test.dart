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
  testWidgets(
      'non segnato: "Presente" con cerchio vuoto; il tocco segna presente',
      (tester) async {
    bool? asked;
    await _pump(
      tester,
      AttendanceToggle(record: null, onChanged: (v) => asked = v),
    );
    expect(find.text('Presente'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    await tester.tap(find.byType(AttendanceToggle));
    expect(asked, isTrue);
  });

  testWidgets('presente: check verde; il tocco segna assente', (tester) async {
    bool? asked;
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(true, AttendanceSource.trainer),
        onChanged: (v) => asked = v,
      ),
    );
    expect(find.text('Presente'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.byType(AttendanceToggle));
    expect(asked, isFalse);
  });

  testWidgets('assente registrato: "Assente", distinto dal non segnato',
      (tester) async {
    bool? asked;
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(false, AttendanceSource.trainer),
        onChanged: (v) => asked = v,
      ),
    );
    expect(find.text('Assente'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byType(AttendanceToggle));
    expect(asked, isTrue);
  });

  testWidgets('pending: spinner e tocco disabilitato', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      AttendanceToggle(record: null, pending: true, onChanged: (_) => calls++),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AttendanceToggle));
    expect(calls, 0);
  });

  testWidgets('semantica: bottone con stato toggled', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(true, AttendanceSource.self),
        onChanged: (_) {},
      ),
    );
    expect(
      tester.getSemantics(find.byType(AttendanceToggle)),
      matchesSemantics(
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: 'Presente',
      ),
    );
    handle.dispose();
  });

  testWidgets('larghezza fissa tra gli stati e area di tocco ≥ 48 px',
      (tester) async {
    await _pump(tester, AttendanceToggle(record: null, onChanged: (_) {}));
    final unmarked = tester.getSize(find.byType(AttendanceToggle));
    await _pump(
      tester,
      AttendanceToggle(
        record: _rec(false, AttendanceSource.admin),
        onChanged: (_) {},
      ),
    );
    final absent = tester.getSize(find.byType(AttendanceToggle));
    expect(absent.width, unmarked.width);
    expect(unmarked.height, greaterThanOrEqualTo(48));
  });

  group('compatta (mobile): solo icona', () {
    testWidgets('niente testo, 48x48, icone per stato', (tester) async {
      await _pump(
        tester,
        AttendanceToggle(record: null, compact: true, onChanged: (_) {}),
      );
      expect(find.text('Presente'), findsNothing);
      expect(tester.getSize(find.byType(AttendanceToggle)), const Size(48, 48));

      await _pump(
        tester,
        AttendanceToggle(
          record: _rec(true, AttendanceSource.trainer),
          compact: true,
          onChanged: (_) {},
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Presente'), findsNothing);

      await _pump(
        tester,
        AttendanceToggle(
          record: _rec(false, AttendanceSource.trainer),
          compact: true,
          onChanged: (_) {},
        ),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Assente'), findsNothing);
    });

    testWidgets('il tocco alterna come la versione estesa', (tester) async {
      bool? asked;
      await _pump(
        tester,
        AttendanceToggle(
          record: _rec(true, AttendanceSource.trainer),
          compact: true,
          onChanged: (v) => asked = v,
        ),
      );
      await tester.tap(find.byType(AttendanceToggle));
      expect(asked, isFalse);
    });

    testWidgets('pending: spinner e tocco disabilitato', (tester) async {
      var calls = 0;
      await _pump(
        tester,
        AttendanceToggle(
          record: null,
          compact: true,
          pending: true,
          onChanged: (_) => calls++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(AttendanceToggle));
      expect(calls, 0);
    });

    testWidgets('etichetta accessibile invariata', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AttendanceToggle(
          record: _rec(false, AttendanceSource.trainer),
          compact: true,
          semanticsLabel: 'Mario Rossi: assente',
          onChanged: (_) {},
        ),
      );
      expect(find.bySemanticsLabel('Mario Rossi: assente'), findsOneWidget);
      handle.dispose();
    });
  });
}
