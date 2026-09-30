import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/components/attendance_toggle.dart';
import 'package:fitrope_app/utils/attendance_window.dart';

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

/// Pill compatta "✓ N" dei presenti (etichetta accessibile "Presenti N").
Finder _presentPill(int n) => find.descendant(
      of: find.byKey(const Key('present-count-pill')),
      matching: find.text('$n'),
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
    Future<void> pumpWithState(WidgetTester tester, CourseState state) async {
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

    testWidgets('resta disabilitato finché la callback asincrona non termina',
        (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await _pump(
        tester,
        CourseCard(
          courseId: 'c1',
          course: _course(),
          title: 'Corso',
          courseState: CourseState.CAN_SUBSCRIBE,
          onClickAction: () {
            calls++;
            return completion.future;
          },
          onRefresh: () {},
        ),
      );

      final buttonFinder = find.widgetWithText(ElevatedButton, 'Prenotati');
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(calls, 1);
      expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNull);

      completion.complete();
      await tester.pump();
      expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNotNull);
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

    testWidgets('lista vuota espansa mostra "Nessun iscritto"', (tester) async {
      await _pump(tester, adminCard(subscribers: const []));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Nessun iscritto'), findsOneWidget);
    });
  });

  group('senza onClick la card non intercetta i tocchi', () {
    // La tile espandibile del calendario avvolge la card in un GestureDetector
    // per richiuderla al tocco. Se la card tiene un onTap sempre non-null
    // (una callback che controlla `onClick` al suo interno) vince l'arena dei
    // gesti e quel wrapper non riceve mai nulla: la riga aperta resta aperta.
    testWidgets('un tocco arriva al genitore', (tester) async {
      var esterno = 0;
      await _pump(
        tester,
        GestureDetector(
          onTap: () => esterno++,
          child: CourseCard(
            courseId: 'c1',
            course: _course(),
            title: 'Corso Test',
            onRefresh: () {},
          ),
        ),
      );
      await tester.tap(find.text('Corso Test'));
      await tester.pump();
      expect(esterno, 1);
    });

    testWidgets('con onClick il tocco resta alla card', (tester) async {
      var esterno = 0, interno = 0;
      await _pump(
        tester,
        GestureDetector(
          onTap: () => esterno++,
          child: CourseCard(
            courseId: 'c1',
            course: _course(),
            title: 'Corso Test',
            onClick: () => interno++,
            onRefresh: () {},
          ),
        ),
      );
      await tester.tap(find.text('Corso Test'));
      await tester.pump();
      expect(interno, 1);
      expect(esterno, 0);
    });
  });

  testWidgets('Correggi conteggio: aggiorna la card e conferma',
      (tester) async {
    final recounted = <String>[];
    var refreshed = 0;
    await _pump(
      tester,
      CourseCard(
        courseId: 'c1',
        course: _course(capacity: 4, subscribed: 3),
        title: 'Corso',
        capacity: 4,
        subscribed: 3, // il contatore dice 3...
        subscribersUsers: [_user(1)], // ...ma l'iscritto vero è uno
        waitlistUsers: const [],
        showClickableSubscribers: true,
        isAdmin: true,
        userRole: 'Admin',
        onRefresh: () => refreshed++,
        // Lenta come la callable vera (~1 s dopo il cold start): il dialog
        // ha già finito l'animazione di chiusura quando arriva la risposta.
        recountSubscribed: (id) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          recounted.add(id);
        },
      ),
    );

    await tester.tap(find.byTooltip('Correggi conteggio iscritti'));
    await tester.pump();
    await tester.tap(find.text('Correggi'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));

    // Prima del fix il callback usava il context del dialog, già smontato
    // dopo il pop: il server correggeva, ma la card restava com'era.
    expect(recounted, ['c1']);
    expect(refreshed, 1);
    expect(find.text('Conteggio iscritti aggiornato con successo!'),
        findsOneWidget);
  });

  group('presenze', () {
    AttendanceRecord rec(String uid, bool present) => AttendanceRecord(
          courseId: 'c1',
          userId: uid,
          courseStartMillis: 0,
          present: present,
          source: AttendanceSource.trainer,
        );

    Widget staffCard({
      required List<FitropeUser> subscribers,
      bool canMark = true,
      int? markerCount,
      Map<String, AttendanceRecord>? records,
      Set<String> pending = const {},
      VoidCallback? onExpanded,
      void Function(FitropeUser, bool)? onToggle,
    }) =>
        CourseCard(
          courseId: 'c1',
          course: markerCount == null
              ? _course(capacity: 4, subscribed: subscribers.length)
              : _course(capacity: 4, subscribed: subscribers.length).copyWith(
                  attendance:
                      CourseAttendanceSummary(presentCount: markerCount),
                ),
          title: 'Corso',
          capacity: 4,
          subscribed: subscribers.length,
          subscribersUsers: subscribers,
          waitlistUsers: const [],
          showClickableSubscribers: true,
          isAdmin: true,
          userRole: 'Trainer',
          canMarkAttendance: canMark,
          showPresentCount: true,
          attendanceRecords: records,
          pendingAttendanceUids: pending,
          onSubscribersExpanded: onExpanded,
          onToggleAttendance: onToggle ?? (_, __) {},
          onRefresh: () {},
        );

    testWidgets('socio: "Sono in sala" anche con courseState CLOSED',
        (tester) async {
      await _pump(
        tester,
        CourseCard(
          courseId: 'c1',
          course: _course(),
          title: 'Corso',
          capacity: 10,
          subscribed: 3,
          courseState: CourseState.CLOSED,
          selfCheckInState: SelfCheckInState.open,
          onSelfCheckIn: () async => true,
          onRefresh: () {},
        ),
      );
      expect(find.text('Sono in sala'), findsOneWidget);
    });

    testWidgets('socio: "Sono in sala" convive con "Rimuovi iscrizione"',
        (tester) async {
      await _pump(
        tester,
        CourseCard(
          courseId: 'c1',
          course: _course(),
          title: 'Corso',
          capacity: 10,
          subscribed: 3,
          courseState: CourseState.SUBSCRIBED,
          selfCheckInState: SelfCheckInState.open,
          onSelfCheckIn: () async => true,
          onRefresh: () {},
        ),
      );
      expect(find.text('Sono in sala'), findsOneWidget);
      expect(find.text('Rimuovi iscrizione'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Sono in sala'),
          matching: find.byType(Wrap),
        ),
        findsWidgets,
      );
    });

    testWidgets('socio: avviso "chiedi al trainer" sotto le azioni',
        (tester) async {
      await _pump(
        tester,
        CourseCard(
          courseId: 'c1',
          course: _course(),
          title: 'Corso',
          capacity: 10,
          subscribed: 3,
          courseState: CourseState.CLOSED,
          selfCheckInState: SelfCheckInState.closedAskTrainer,
          onRefresh: () {},
        ),
      );
      expect(find.textContaining('chiedi al trainer'), findsOneWidget);
    });

    testWidgets('"Presenti 3" dal marcatore a lista collassata',
        (tester) async {
      await _pump(
        tester,
        staffCard(subscribers: [_user(1), _user(2)], markerCount: 3),
      );
      expect(_presentPill(3), findsOneWidget);
    });

    testWidgets('nessun marcatore e record non caricati: niente pill',
        (tester) async {
      await _pump(tester, staffCard(subscribers: [_user(1)]));
      expect(find.byKey(const Key('present-count-pill')), findsNothing);
    });

    testWidgets('il conteggio locale vince sul marcatore', (tester) async {
      await _pump(
        tester,
        staffCard(
          subscribers: [_user(1), _user(2)],
          markerCount: 3,
          records: {'u1': rec('u1', true), 'u2': rec('u2', false)},
        ),
      );
      expect(_presentPill(1), findsOneWidget);
    });

    testWidgets('staff non titolare: conteggio sì, spunte no', (tester) async {
      await _pump(
        tester,
        staffCard(
          subscribers: [_user(1)],
          canMark: false,
          markerCount: 2,
        ),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(_presentPill(2), findsOneWidget);
      expect(find.byType(AttendanceToggle), findsNothing);
      expect(find.textContaining('Appello'), findsNothing);
    });

    testWidgets('onSubscribersExpanded solo all\'apertura', (tester) async {
      var opened = 0;
      await _pump(
        tester,
        staffCard(subscribers: [_user(1)], onExpanded: () => opened++),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(opened, 1);
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets(
        'titolare: chip per riga; pending disabilitato; tocco inoltrato',
        (tester) async {
      final toggles = <String>[];
      await _pump(
        tester,
        staffCard(
          subscribers: [_user(1), _user(2)],
          records: {'u1': rec('u1', true)},
          pending: {'u2'},
          onToggle: (u, present) => toggles.add('${u.uid}:$present'),
        ),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      final chips = tester
          .widgetList<AttendanceToggle>(find.byType(AttendanceToggle))
          .toList();
      expect(chips, hasLength(2));
      expect(chips[0].record?.present, isTrue);
      expect(chips[0].pending, isFalse);
      expect(chips[1].pending, isTrue);
      await tester.tap(find.byType(AttendanceToggle).first);
      expect(toggles, ['u1:false']);
    });

    testWidgets('record non ancora caricati: tutte le chip in attesa',
        (tester) async {
      await _pump(tester, staffCard(subscribers: [_user(1)]));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(
        tester.widget<AttendanceToggle>(find.byType(AttendanceToggle)).pending,
        isTrue,
      );
      expect(find.text('Caricamento presenze…'), findsOneWidget);
    });

    testWidgets(
        'riepilogo appello: presenti su iscritti, solo iscritti attuali',
        (tester) async {
      await _pump(
        tester,
        staffCard(
          subscribers: [_user(1), _user(2)],
          // u9 era presente ma non è più iscritto: non conta.
          records: {'u1': rec('u1', true), 'u9': rec('u9', true)},
        ),
      );
      expect(_presentPill(1), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Appello'), findsOneWidget);
      expect(find.text('1 su 2 presenti'), findsOneWidget);
    });

    testWidgets(
        'check-in del socio: didascalia sotto il nome, riga ad altezza fissa',
        (tester) async {
      AttendanceRecord self(String uid) => AttendanceRecord(
            courseId: 'c1',
            userId: uid,
            courseStartMillis: 0,
            present: true,
            source: AttendanceSource.self,
          );
      await _pump(
        tester,
        staffCard(subscribers: [_user(1), _user(2)], records: null),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      final before = tester.getSize(find.byKey(const Key('appello-row-u1')));

      await _pump(
        tester,
        staffCard(
          subscribers: [_user(1), _user(2)],
          records: {'u1': self('u1')},
        ),
      );
      await tester.pump();
      expect(find.text('check-in del socio'), findsOneWidget);
      final after = tester.getSize(find.byKey(const Key('appello-row-u1')));
      expect(after.height, before.height);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('header iscritti a 360 px (testo x$scale): nessun overflow',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: CourseCard(
                  courseId: 'c1',
                  course: _course(capacity: 20, subscribed: 4).copyWith(
                    attendance: const CourseAttendanceSummary(presentCount: 12),
                  ),
                  title: 'Corso',
                  capacity: 20,
                  subscribed: 4,
                  subscribersUsers: [_user(1), _user(2), _user(3), _user(4)],
                  waitlistUsers: const [],
                  showClickableSubscribers: true,
                  isAdmin: true,
                  userRole: 'Admin',
                  showPresentCount: true,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_presentPill(12), findsOneWidget);
      });
    }

    testWidgets('riga appello con testo grande: nessun overflow',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 800),
            textScaler: TextScaler.linear(2.0),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: staffCard(
                subscribers: [_user(1)],
                records: {
                  'u1': const AttendanceRecord(
                    courseId: 'c1',
                    userId: 'u1',
                    courseStartMillis: 0,
                    present: true,
                    source: AttendanceSource.self,
                  ),
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('spunta accessibile: etichetta con il nome e lo stato',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        staffCard(subscribers: [_user(1)], records: {'u1': rec('u1', false)}),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.bySemanticsLabel('Iscritto 1: assente'), findsOneWidget);
      handle.dispose();
    });

    // 400 px con il font di test (Ahem, glifi ~2x più larghi di Roboto) è
    // più severo di un telefono reale da 360 px; il 360 reale è verificato
    // nel browser.
    testWidgets('mobile: nessun overflow con nomi lunghi', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final longName = FitropeUser(
        uid: 'u1',
        name: 'Massimiliano Alessandro',
        lastName: 'Della Rosa Bonaventura',
        email: 'u1@example.com',
        courses: const [],
        role: 'User',
        createdAt: DateTime(2026, 1, 1),
      );
      await _pump(
        tester,
        staffCard(subscribers: [longName], records: {'u1': rec('u1', true)}),
      );
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
