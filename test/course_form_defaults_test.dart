import 'package:fitrope_app/utils/course_form_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prima delle 19 propone oggi alle 19', () {
    final result = nextDefaultCourseStart(DateTime(2026, 8, 20, 18, 59));
    expect(result, DateTime(2026, 8, 20, 19));
  });

  test('alle 19 o dopo propone domani alle 19 anche a fine mese', () {
    expect(
      nextDefaultCourseStart(DateTime(2026, 8, 31, 19)),
      DateTime(2026, 9, 1, 19),
    );
    expect(
      nextDefaultCourseStart(DateTime(2026, 12, 31, 23)),
      DateTime(2027, 1, 1, 19),
    );
  });
}
