import 'package:fitrope_app/utils/recurring_course_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('genera soltanto i giorni selezionati nel range inclusivo', () {
    final dates = calculateRecurringCourseDates(
      start: DateTime(2026, 8, 3, 19, 30),
      end: DateTime(2026, 8, 12),
      weekdays: {DateTime.monday, DateTime.wednesday},
    );
    expect(
      dates,
      [
        DateTime(2026, 8, 3, 19, 30),
        DateTime(2026, 8, 5, 19, 30),
        DateTime(2026, 8, 10, 19, 30),
        DateTime(2026, 8, 12, 19, 30),
      ],
    );
  });

  test('range invertito o nessun giorno non genera corsi', () {
    expect(
      calculateRecurringCourseDates(
        start: DateTime(2026, 8, 5),
        end: DateTime(2026, 8, 3),
        weekdays: {DateTime.monday},
      ),
      isEmpty,
    );
    expect(
      calculateRecurringCourseDates(
        start: DateTime(2026, 8, 3),
        end: DateTime(2026, 8, 5),
        weekdays: {},
      ),
      isEmpty,
    );
  });
}
