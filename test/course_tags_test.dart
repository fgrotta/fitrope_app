import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/course_tags.dart';

void main() {
  group('CourseTags.canUserAccessCourse', () {
    group('empty tags', () {
      test('user with no tags and course with no tags: can access', () {
        expect(CourseTags.canUserAccessCourse([], []), true);
      });

      test('user with no tags and course with OPEN tag: can access', () {
        expect(CourseTags.canUserAccessCourse([], [CourseTags.OPEN]), true);
      });

      test('user with OPEN tag and course with no tags: can access', () {
        expect(CourseTags.canUserAccessCourse([CourseTags.OPEN], []), true);
      });

      test('user with no tags and course with restricted tag: cannot access', () {
        expect(CourseTags.canUserAccessCourse([], [CourseTags.PERSONAL_TRAINER]), false);
      });
    });

    group('matching tags', () {
      test('user has same tag as course: can access', () {
        expect(
          CourseTags.canUserAccessCourse(
            [CourseTags.PERSONAL_TRAINER],
            [CourseTags.PERSONAL_TRAINER],
          ),
          true,
        );
      });

      test('user has HEY_MAMMA tag matching course: can access', () {
        expect(
          CourseTags.canUserAccessCourse(
            [CourseTags.HEY_MAMMA],
            [CourseTags.HEY_MAMMA],
          ),
          true,
        );
      });

      test('user has multiple tags, one matches: can access', () {
        expect(
          CourseTags.canUserAccessCourse(
            [CourseTags.OPEN, CourseTags.PERSONAL_TRAINER],
            [CourseTags.PERSONAL_TRAINER],
          ),
          true,
        );
      });
    });

    group('no matching tags', () {
      test('user has OPEN tag but course requires PERSONAL_TRAINER: cannot access', () {
        expect(
          CourseTags.canUserAccessCourse(
            [CourseTags.OPEN],
            [CourseTags.PERSONAL_TRAINER],
          ),
          false,
        );
      });

      test('user has HEY_MAMMA but course is PERSONAL_TRAINER: cannot access', () {
        expect(
          CourseTags.canUserAccessCourse(
            [CourseTags.HEY_MAMMA],
            [CourseTags.PERSONAL_TRAINER],
          ),
          false,
        );
      });
    });

    group('constants', () {
      test('OPEN constant is defined', () {
        expect(CourseTags.OPEN, 'Open');
      });

      test('PERSONAL_TRAINER constant is defined', () {
        expect(CourseTags.PERSONAL_TRAINER, 'Personal Trainer');
      });

      test('HEY_MAMMA constant is defined', () {
        expect(CourseTags.HEY_MAMMA, 'Hey Mamma');
      });

      test('all() returns all available tags', () {
        expect(CourseTags.all, containsAll([CourseTags.PERSONAL_TRAINER, CourseTags.OPEN, CourseTags.HEY_MAMMA]));
      });

      test('defaultUserTags returns OPEN', () {
        expect(CourseTags.defaultUserTags, [CourseTags.OPEN]);
      });
    });
  });
}
