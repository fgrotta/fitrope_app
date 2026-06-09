import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/course_tags.dart';

/// Test per CourseTags.canUserAccessCourse.
/// Questa logica determina se un utente puo iscriversi a un corso in base ai tag.
/// Precedentemente priva di copertura: la scorrettezza qui blocca silenziosamente
/// gli utenti (ritornando CourseState.NULL da getCourseState).
void main() {
  group('CourseTags.canUserAccessCourse', () {
    test('utente con "Tutti i corsi" accede sempre, anche se corso ha tag specifici', () {
      expect(
        CourseTags.canUserAccessCourse(
          ['Tutti i corsi'],
          [CourseTags.PERSONAL_TRAINER, CourseTags.HEY_MAMMA],
        ),
        true,
      );
    });

    test('utente con "Tutti i corsi" accede anche a corso senza tag', () {
      expect(
        CourseTags.canUserAccessCourse(['Tutti i corsi'], const []),
        true,
      );
    });

    test('utente senza tag accede a corso senza tag', () {
      expect(CourseTags.canUserAccessCourse(const [], const []), true);
    });

    test('utente senza tag accede a corso OPEN', () {
      expect(
        CourseTags.canUserAccessCourse(const [], [CourseTags.OPEN]),
        true,
      );
    });

    test('utente OPEN accede a corso senza tag', () {
      expect(
        CourseTags.canUserAccessCourse([CourseTags.OPEN], const []),
        true,
      );
    });

    test('utente OPEN NON accede a corso Personal Trainer', () {
      expect(
        CourseTags.canUserAccessCourse(
          [CourseTags.OPEN],
          [CourseTags.PERSONAL_TRAINER],
        ),
        false,
      );
    });

    test('utente Personal Trainer accede a corso Personal Trainer', () {
      expect(
        CourseTags.canUserAccessCourse(
          [CourseTags.PERSONAL_TRAINER],
          [CourseTags.PERSONAL_TRAINER],
        ),
        true,
      );
    });

    test('utente Personal Trainer NON accede a corso OPEN', () {
      expect(
        CourseTags.canUserAccessCourse(
          [CourseTags.PERSONAL_TRAINER],
          [CourseTags.OPEN],
        ),
        false,
      );
    });

    test('utente con almeno un tag matching accede al corso', () {
      expect(
        CourseTags.canUserAccessCourse(
          [CourseTags.PERSONAL_TRAINER, CourseTags.HEY_MAMMA],
          [CourseTags.HEY_MAMMA],
        ),
        true,
      );
    });

    test('utente con tag sconosciuti NON accede al corso', () {
      expect(
        CourseTags.canUserAccessCourse(
          ['Tag Sconosciuto'],
          [CourseTags.OPEN],
        ),
        false,
      );
    });

    test('utente senza tag NON accede a corso con tag diverso da OPEN', () {
      expect(
        CourseTags.canUserAccessCourse(
          const [],
          [CourseTags.HEY_MAMMA],
        ),
        false,
      );
    });

    test('defaultUserTags contiene OPEN', () {
      expect(CourseTags.defaultUserTags, contains(CourseTags.OPEN));
    });

    test('all contiene tutti i tag documentati', () {
      expect(CourseTags.all, containsAll([
        CourseTags.PERSONAL_TRAINER,
        CourseTags.OPEN,
        CourseTags.HEY_MAMMA,
      ]));
    });
  });
}
