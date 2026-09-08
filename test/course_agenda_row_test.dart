import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_agenda_row.dart';
import 'package:fitrope_app/components/course_card.dart' show CourseState;
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Course course({
    String name = 'Pilates Matwork',
    List<String> tags = const [CourseTags.OPEN],
    String? sala = 'Sala 2',
    int capacity = 12,
    int subscribed = 5,
  }) =>
      Course(
        id: 'c1',
        uid: 'c1',
        name: name,
        startDate: Timestamp.fromDate(DateTime(2026, 8, 26, 9)),
        endDate: Timestamp.fromDate(DateTime(2026, 8, 26, 10)),
        capacity: capacity,
        subscribed: subscribed,
        tags: tags,
        sala: sala,
      );

  Future<void> pump(
    WidgetTester tester, {
    Course? c,
    CourseState state = CourseState.CAN_SUBSCRIBE,
    String trainerName = 'Giulia Rossi',
    VoidCallback? onTap,
    VoidCallback? onAction,
    double width = 390,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: CourseAgendaRow(
              course: c ?? course(),
              courseState: state,
              trainerName: trainerName,
              onTap: onTap ?? () {},
              onAction: onAction ?? () {},
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('mostra orario, titolo, sala e trainer', (tester) async {
    await pump(tester);
    // La colonna orario è su due righe: inizio sopra, fine sotto. È la spina
    // dell'agenda, e su due righe non ruba larghezza al titolo.
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('Pilates Matwork'), findsOneWidget);
    expect(find.textContaining('Sala 2'), findsOneWidget);
    expect(find.textContaining('Giulia Rossi'), findsOneWidget);
  });

  testWidgets('un corso senza sala lo dice, non lascia il posto vuoto',
      (tester) async {
    await pump(tester, c: course(sala: null));
    expect(find.textContaining('Nessuna sala'), findsOneWidget);
  });

  testWidgets('mostra la pill della capienza', (tester) async {
    await pump(tester);
    expect(find.text('7 liberi'), findsOneWidget);
  });

  testWidgets('mostra il pulsante con l\'etichetta dello stato',
      (tester) async {
    await pump(tester, state: CourseState.CAN_WAITLIST);
    expect(find.text("Lista d'attesa"), findsOneWidget);
  });

  testWidgets('CLOSED: nessun pulsante, il corso è passato', (tester) async {
    await pump(tester, state: CourseState.CLOSED);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('toccare la riga la apre', (tester) async {
    var tapped = 0;
    await pump(tester, onTap: () => tapped++);
    await tester.tap(find.byKey(const Key('agenda-row-c1')));
    expect(tapped, 1);
  });

  testWidgets('toccare il pulsante prenota e NON apre la riga', (tester) async {
    var tapped = 0, acted = 0;
    await pump(tester, onTap: () => tapped++, onAction: () => acted++);
    await tester.tap(find.byKey(const Key('agenda-row-action-c1')));
    await tester.pump();
    expect(acted, 1, reason: 'il pulsante deve agire');
    expect(tapped, 0, reason: 'e non deve propagare l\'apertura alla riga');
  });

  testWidgets('porta l\'accento colore della tipologia', (tester) async {
    await pump(tester, c: course(tags: const [CourseTags.HYROX]));
    expect(find.byKey(const Key('agenda-row-accent-c1')), findsOneWidget);
  });

  testWidgets('mostra il chevron di apertura sulla miniatura', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('agenda-row-chevron-c1')), findsOneWidget);
  });

  group('desktop (da 900 px)', () {
    testWidgets('la riga sta su una sola linea, quindi è più bassa',
        (tester) async {
      // Su mobile titolo e meta sono impilati (due linee); da 900px in su la
      // meta va in una colonna propria accanto al titolo, così la riga si
      // schiaccia e non resta il vuoto enorme fra titolo e azione.
      await pump(tester, width: 390);
      final mobile = tester.getSize(find.byType(CourseAgendaRow)).height;

      await pump(tester, width: 1200);
      final desktop = tester.getSize(find.byType(CourseAgendaRow)).height;

      expect(desktop, lessThan(mobile));
    });

    testWidgets('mostra comunque titolo, meta, posti e azione', (tester) async {
      await pump(tester, width: 1200);
      expect(find.text('Pilates Matwork'), findsOneWidget);
      expect(find.textContaining('Sala 2'), findsOneWidget);
      expect(find.textContaining('Giulia Rossi'), findsOneWidget);
      expect(find.text('7 liberi'), findsOneWidget);
      expect(find.text('Prenotati'), findsOneWidget);
    });

    testWidgets('non va in overflow a 1200 px', (tester) async {
      await pump(tester, width: 1200, state: CourseState.SUBSCRIBED);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('non va in overflow a 390 px con un titolo lungo',
      (tester) async {
    await pump(tester,
        c: course(name: 'Functional Morning Total Body Extra Lungo'),
        state: CourseState.SUBSCRIBED);
    expect(tester.takeException(), isNull);
  });
}
