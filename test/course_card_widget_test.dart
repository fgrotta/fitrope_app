import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

/// Primi widget test del progetto: rendering della CourseCard,
/// pill capienza, viste utente/admin, stati del bottone iscrizione
/// ed espansione della lista iscritti.
Course _course({int capacity = 10, int subscribed = 3}) => Course(
      id: 'c1',
      uid: 'c1',
      name: 'Corso Test',
      startDate: Timestamp.fromDate(DateTime(2026, 6, 9, 10)),
      endDate: Timestamp.fromDate(DateTime(2026, 6, 9, 11)),
      capacity: capacity,
      subscribed: subscribed,
      courseType: CourseType.open,
    );

FitropeUser _user(int i) => FitropeUser(
      uid: 'u$i',
      name: 'Iscritto',
      lastName: '$i',
      email: 'u$i@example.com',
      courses: const [],
      role: 'User',
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  // Un singolo pump: niente pumpAndSettle (lo stream dell'immagine di
  // sfondo non si stabilizza nel test bundle).
  await tester.pump();
}

void main() {
  testWidgets('mostra il titolo del corso', (tester) async {
    await _pump(
      tester,
      CourseCard(
        courseId: 'c1',
        course: _course(),
        title: 'Open Mattina',
        onRefresh: () {},
      ),
    );
    expect(find.text('Open Mattina'), findsOneWidget);
  });

  testWidgets('vista utente: pill posti liberi e bottone iscritti',
      (tester) async {
    await _pump(
      tester,
      CourseCard(
        courseId: 'c1',
        course: _course(),
        title: 'Corso',
        capacity: 10,
        subscribed: 3,
        onRefresh: () {},
      ),
    );
    expect(find.text('7 liberi'), findsOneWidget);
    expect(find.byTooltip('Vedi iscritti'), findsOneWidget);
  });

  testWidgets('vista admin: azioni corso e nessun bottone utente',
      (tester) async {
    await _pump(
      tester,
      CourseCard(
        courseId: 'c1',
        course: _course(),
        title: 'Corso',
        capacity: 10,
        subscribed: 3,
        isAdmin: true,
        userRole: 'Admin',
        onEdit: () {},
        onDuplicate: () {},
        onDelete: () {},
        onRefresh: () {},
      ),
    );
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
    expect(find.byTooltip('Vedi iscritti'), findsNothing);
  });

  group('bottone iscrizione per stato', () {
    Future<void> pumpWithState(
        WidgetTester tester, CourseState state) async {
      await _pump(
        tester,
        CourseCard(
          courseId: 'c1',
          course: _course(),
          title: 'Corso',
          courseState: state,
          onRefresh: () {},
        ),
      );
    }

    testWidgets('CAN_SUBSCRIBE -> Prenotati', (tester) async {
      await pumpWithState(tester, CourseState.CAN_SUBSCRIBE);
      expect(find.text('Prenotati'), findsOneWidget);
    });

    testWidgets('SUBSCRIBED -> Rimuovi iscrizione', (tester) async {
      await pumpWithState(tester, CourseState.SUBSCRIBED);
      expect(find.text('Rimuovi iscrizione'), findsOneWidget);
    });

    testWidgets('FULL -> Corso pieno', (tester) async {
      await pumpWithState(tester, CourseState.FULL);
      expect(find.text('Corso pieno'), findsOneWidget);
    });

    testWidgets('CLOSED -> nessun bottone', (tester) async {
      await pumpWithState(tester, CourseState.CLOSED);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });

  group('lista iscritti espandibile (vista admin)', () {
    Widget adminCard({required List<FitropeUser> subscribers}) => CourseCard(
          courseId: 'c1',
          course: _course(capacity: 4, subscribed: subscribers.length),
          title: 'Corso',
          capacity: 4,
          subscribed: subscribers.length,
          subscribersUsers: subscribers,
          waitlistUsers: const [],
          showClickableSubscribers: true,
          isAdmin: true,
          userRole: 'Admin',
          onRefresh: () {},
        );

    testWidgets('collassata di default: nomi nascosti, barra visibile',
        (tester) async {
      await _pump(tester, adminCard(subscribers: [_user(1), _user(2)]));
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
      expect(find.textContaining('• Iscritto'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('tap sull\'header espande e mostra i nomi', (tester) async {
      await _pump(tester, adminCard(subscribers: [_user(1), _user(2)]));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.textContaining('• Iscritto'), findsNWidgets(2));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('lista vuota espansa mostra "Nessun iscritto"',
        (tester) async {
      await _pump(tester, adminCard(subscribers: const []));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Nessun iscritto'), findsOneWidget);
    });
  });
}
