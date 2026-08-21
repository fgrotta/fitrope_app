import 'package:fitrope_app/pages/protected/recurring_course_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _admin = FitropeUser(
  uid: 'admin',
  email: 'admin@example.com',
  name: 'Admin',
  lastName: 'Test',
  courses: const [],
  role: 'Admin',
  createdAt: DateTime(2026),
);

Future<void> pumpRecurring(
  WidgetTester tester,
  Future<Course?> Function(Course) create,
) async {
  store.dispatch(SetUserAction(_admin));
  await tester.binding.setSurfaceSize(const Size(1000, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RecurringCoursePage(
        loadTrainers: () async => [],
        createCourseOperation: create,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapRecurringSubmit(WidgetTester tester) async {
  final submit = find.byKey(const Key('recurring-course-submit-button'));
  tester.widget<ElevatedButton>(submit).onPressed!.call();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('richiede nome e almeno un giorno', (tester) async {
    await pumpRecurring(tester, (_) async => null);
    await tapRecurringSubmit(tester);
    expect(find.text('Il nome del corso è obbligatorio'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recurring-course-name-field')),
      'Open ricorrente',
    );
    await tapRecurringSubmit(tester);
    expect(
      find.text('Seleziona almeno un giorno della settimana'),
      findsOneWidget,
    );
  });

  testWidgets('genera tutti e soli i corsi del weekday selezionato',
      (tester) async {
    final created = <Course>[];
    await pumpRecurring(tester, (course) async {
      created.add(course);
      return course;
    });
    await tester.enterText(
      find.byKey(const Key('recurring-course-name-field')),
      'Open ricorrente',
    );
    final selectedWeekday = DateTime.now().add(const Duration(days: 1)).weekday;
    final weekday =
        find.byKey(Key('recurring-course-weekday-$selectedWeekday'));
    await tester.ensureVisible(weekday);
    await tester.tap(weekday);
    await tester.pump();

    final submit = find.byKey(const Key('recurring-course-submit-button'));
    await tester.ensureVisible(submit);
    expect(find.descendant(of: submit, matching: find.textContaining('Crea ')),
        findsOneWidget);
    await tapRecurringSubmit(tester);
    await tester.pumpAndSettle();

    expect(created.length, greaterThanOrEqualTo(4));
    expect(
      created.every((course) =>
          course.startDate.toDate().toLocal().weekday == selectedWeekday),
      isTrue,
    );
    expect(created.every((course) => course.name == 'Open ricorrente'), isTrue);
  });
}
