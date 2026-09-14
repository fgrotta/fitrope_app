import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/get_course_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Regressione sulla **fedeltà visiva**, che è il requisito primario della
/// modalità simulazione.
///
/// La guardia read-only (Layer A) sta nei callback delle *pagine*, non nella
/// card: la `CourseCard` deve quindi continuare a calcolare il proprio
/// `CourseState` dall'utente simulato e restare **colorata e cliccabile**.
/// Vedere *se* il bottone sarebbe premibile è metà del valore diagnostico —
/// una card grigia o nascosta sarebbe il bug, non la protezione.
void main() {
  tearDown(SimulationSession.stop);

  final admin = simUser(uid: 'admin-1', role: 'Admin');

  Course course({int subscribed = 3, int capacity = 10}) => Course(
        id: 'c1',
        uid: 'c1',
        name: 'Corso Test',
        startDate:
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 2, hours: 1))),
        capacity: capacity,
        subscribed: subscribed,
        tags: const [CourseTags.OPEN],
      );

  /// Utente simulato idoneo: abbonamento vivo e tag compatibile.
  FitropeUser simulato({List<String> courses = const []}) => FitropeUser(
        uid: 'user-1',
        name: 'Mario',
        lastName: 'Rossi',
        email: 'mario@example.com',
        role: 'User',
        courses: courses,
        createdAt: DateTime(2026, 1, 1),
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 10,
        fineIscrizione:
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 60))),
        tipologiaCorsoTags: const [CourseTags.OPEN],
      );

  Future<CourseState> pumpCard(
    WidgetTester tester, {
    required Course c,
    required FitropeUser user,
  }) async {
    final state = getCourseState(c, user);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CourseCard(
            courseId: c.uid,
            course: c,
            title: c.name,
            capacity: c.capacity,
            subscribed: c.subscribed,
            courseState: state,
            userRole: user.role,
            onClickAction: () async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    // Un solo pump: lo stream dell'immagine di sfondo non si stabilizza nel
    // test bundle (stessa scelta di course_card_widget_test.dart).
    await tester.pump();

    return state;
  }

  ElevatedButton buttonOf(WidgetTester tester) => tester
      .widget<ElevatedButton>(find.byKey(const Key('course-action-button-c1')));

  testWidgets(
      'in simulazione la card usa lo stato dell\'utente simulato ed è cliccabile',
      (tester) async {
    final user = simulato();
    SimulationSession.start(admin: admin, target: user);

    final state = await pumpCard(tester, c: course(), user: user);

    // Lo stato è quello dell'utente simulato, non dell'admin.
    expect(state, getCourseState(course(), user));
    expect(state, CourseState.CAN_SUBSCRIBE);
    // NON grigio: il bottone resta attivo, la guardia agisce nella pagina.
    expect(buttonOf(tester).onPressed, isNotNull);
    expect(find.text('Prenotati'), findsOneWidget);
  });

  testWidgets(
      'un utente simulato già iscritto vede "Rimuovi iscrizione", attivo',
      (tester) async {
    final user = simulato(courses: const ['c1']);
    SimulationSession.start(admin: admin, target: user);

    final state = await pumpCard(tester, c: course(), user: user);

    expect(state, CourseState.SUBSCRIBED);
    expect(find.text('Rimuovi iscrizione'), findsOneWidget);
    expect(buttonOf(tester).onPressed, isNotNull);
  });

  testWidgets(
      'la simulazione non altera il CourseState: identico a sessione spenta',
      (tester) async {
    final user = simulato();
    final c = course();

    final spenta = getCourseState(c, user);
    SimulationSession.start(admin: admin, target: user);
    final accesa = getCourseState(c, user);

    expect(accesa, spenta);
  });
}
