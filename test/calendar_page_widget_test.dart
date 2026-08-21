import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/calendar_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

final _member = FitropeUser(
  uid: 'member',
  email: 'member@example.com',
  name: 'Mario',
  lastName: 'Rossi',
  courses: const [],
  role: 'User',
  createdAt: DateTime(2026),
  tipologiaCorsoTags: const ['Open', 'Hyrox'],
);

Course calendarCourse(String uid, String tag, DateTime wallClock) => Course(
      id: uid, // ignore: deprecated_member_use_from_same_package
      uid: uid,
      name: '$tag test',
      startDate: italianTimestamp(wallClock),
      endDate: Timestamp.fromDate(
        italianTimestamp(wallClock).toDate().add(const Duration(hours: 1)),
      ),
      capacity: 10,
      subscribed: 0,
      tags: [tag],
    );

Future<void> pumpCalendar(
  WidgetTester tester, {
  required double width,
  required List<Course> courses,
  FitropeUser? user,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  store.dispatch(SetUserAction(user ?? _member));
  await tester.pumpWidget(
    StoreProvider(
      store: store,
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: CalendarPage(
              key: ValueKey(user?.uid ?? _member.uid),
              loadCourses: () async => courses,
              loadTrainers: () async => [],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    initItalianTime();
    await initializeDateFormatting('it_IT');
  });

  testWidgets('mobile filtra per tag e resetta il filtro cambiando giorno',
      (tester) async {
    final today = toItalianTime(DateTime.now());
    final wallClock = DateTime(today.year, today.month, today.day, 19);
    final courses = [
      calendarCourse('open-today', 'Open', wallClock),
      calendarCourse('hyrox-today', 'Hyrox', wallClock),
    ];
    await pumpCalendar(tester, width: 500, courses: courses);

    expect(find.byKey(const Key('course-card-open-today')), findsOneWidget);
    expect(find.byKey(const Key('course-card-hyrox-today')), findsOneWidget);
    expect(find.text('Vista mese'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-tag-filter-Hyrox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('course-card-open-today')), findsNothing);
    expect(find.byKey(const Key('course-card-hyrox-today')), findsOneWidget);

    final otherDay = today.weekday == DateTime.sunday
        ? DateTime(today.year, today.month, today.day - 1)
        : DateTime(today.year, today.month, today.day + 1);
    final otherDayKey = Key(
      'calendar-week-day-${DateFormat('yyyy-MM-dd').format(otherDay)}',
    );
    await tester.tap(find.byKey(otherDayKey));
    await tester.pumpAndSettle();
    expect(find.text('Nessun corso programmato in questa giornata'),
        findsOneWidget);
    expect(find.byKey(const Key('calendar-tag-filter-Hyrox')), findsNothing);
  });

  testWidgets(
      'desktop parte dalla vista mese e mostra le CTA staff solo a staff',
      (tester) async {
    await pumpCalendar(tester, width: 1200, courses: []);
    expect(find.text('Vista settimana'), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-create-course-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('calendar-recurring-course-button')),
      findsNothing,
    );

    final admin = FitropeUser(
      uid: 'admin',
      email: 'admin@example.com',
      name: 'Anna',
      lastName: 'Admin',
      courses: const [],
      role: 'Admin',
      createdAt: DateTime(2026),
    );
    await pumpCalendar(tester, width: 1200, courses: [], user: admin);
    expect(
      find.byKey(const Key('calendar-create-course-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-recurring-course-button')),
      findsOneWidget,
    );
  });
}
