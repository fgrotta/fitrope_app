import 'dart:async';

import 'package:fitrope_app/components/self_checkin_button.dart';
import 'package:fitrope_app/utils/attendance_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

void main() {
  testWidgets('open: bottone "Sono in sala" che invoca la callback',
      (tester) async {
    var calls = 0;
    await _pump(
      tester,
      SelfCheckInButton(
        state: SelfCheckInState.open,
        onCheckIn: () async {
          calls++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Sono in sala'));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('open: lock mentre la richiesta è in volo', (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    await _pump(
      tester,
      SelfCheckInButton(
        state: SelfCheckInState.open,
        onCheckIn: () {
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('Sono in sala'));
    await tester.pump();
    await tester.tap(find.text('Sono in sala'));
    await tester.pump();
    expect(calls, 1);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    pending.complete(true);
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('presentSelf / presentStaff: pill senza bottone', (tester) async {
    await _pump(
      tester,
      const SelfCheckInButton(state: SelfCheckInState.presentSelf),
    );
    expect(find.text('Presente'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);

    await _pump(
      tester,
      const SelfCheckInButton(state: SelfCheckInState.presentStaff),
    );
    expect(find.text('Presenza registrata'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('closedAskTrainer e absentStaff: avvisi inline, niente dialog',
      (tester) async {
    await _pump(
      tester,
      const SelfCheckInButton(state: SelfCheckInState.closedAskTrainer),
    );
    expect(
      find.text(
          'Check-in chiuso: chiedi al trainer di registrare la tua presenza'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);

    await _pump(
      tester,
      const SelfCheckInButton(state: SelfCheckInState.absentStaff),
    );
    expect(
      find.text('Risulti assente. Se eri in sala, chiedi al trainer di '
          'correggere'),
      findsOneWidget,
    );
    expect(SelfCheckInButton.isNotice(SelfCheckInState.absentStaff), isTrue);
    expect(SelfCheckInButton.isNotice(SelfCheckInState.open), isFalse);
  });

  testWidgets('notYetOpen: niente di visibile', (tester) async {
    await _pump(
      tester,
      const SelfCheckInButton(state: SelfCheckInState.notYetOpen),
    );
    expect(find.byType(Text), findsNothing);
  });
}
