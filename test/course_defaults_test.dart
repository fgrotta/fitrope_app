import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Personal Trainer ha capienza di default pari a uno', () {
    expect(defaultCapacityForCourseType(CourseType.personal_trainer), 1);
  });

  test('Open ha capienza di default pari a sei', () {
    expect(defaultCapacityForCourseType(CourseType.open), 6);
  });
}
