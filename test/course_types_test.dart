import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';

void main() {
  group('CourseTags', () {
    test('lista chiusa degli otto tag descrittivi', () {
      expect(CourseTags.selectable.toSet(), {
        CourseTags.PERSONAL_TRAINER,
        CourseTags.HYROX,
        CourseTags.YOGA,
        CourseTags.PILATES,
        CourseTags.CALISTHENICS,
        CourseTags.POSTURALE,
        CourseTags.TABATA,
        CourseTags.FITROPE,
      });
      expect(CourseTags.selectable, isNot(contains(CourseTags.OPEN)));
      expect(CourseTags.selectable, isNot(contains(CourseTags.HEY_MAMMA)));
      expect(CourseTags.legacyReadOnly, {CourseTags.HEY_MAMMA});
    });

    test('mirror type-first e deduplicato', () {
      expect(CourseTags.legacyTagsMirror('Open', null), ['Open']);
      expect(CourseTags.legacyTagsMirror('Open', 'Yoga'), ['Open', 'Yoga']);
      expect(
          CourseTags.legacyTagsMirror('Personal Trainer', 'Personal Trainer'),
          ['Personal Trainer']);
    });
  });

  group('CourseTypes registry', () {
    test('contiene solo Open e Personal Trainer', () {
      expect(CourseTypes.all, [CourseTypes.open, CourseTypes.personalTrainer]);
      expect(CourseTypes.open.family, SubscriptionFamily.OPEN);
      expect(CourseTypes.personalTrainer.family, SubscriptionFamily.PT);
      expect(CourseTypes.byKey(CourseTags.HYROX), isNull);
      expect(CourseTypes.byKey(CourseTags.HEY_MAMMA), isNull);
    });

    test('resolver V1 tratta Hyrox come Open', () {
      expect(CourseTypes.primaryForTags([CourseTags.HYROX]), CourseTypes.open);
      expect(CourseTypes.primaryForTags([CourseTags.PERSONAL_TRAINER]),
          CourseTypes.personalTrainer);
      expect(CourseTypes.primaryForTags(['Sconosciuto']), isNull);
    });

    test('defaultSala, se valorizzata, e valida', () {
      for (final type in CourseTypes.all) {
        expect(Sale.isValid(type.defaultSala), true);
      }
    });
  });
}
