import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';

void main() {
  group('CourseTags', () {
    test('all include il nuovo tag Hyrox', () {
      expect(CourseTags.all, contains(CourseTags.HYROX));
    });

    test('all mantiene i tag preesistenti', () {
      expect(
          CourseTags.all,
          containsAll([
            CourseTags.PERSONAL_TRAINER,
            CourseTags.OPEN,
            CourseTags.HEY_MAMMA,
          ]));
    });
  });

  group('CourseTypes registry', () {
    test('le chiavi coincidono con i tag (nessuna migrazione richiesta)', () {
      expect(CourseTypes.open.key, CourseTags.OPEN);
      expect(CourseTypes.personalTrainer.key, CourseTags.PERSONAL_TRAINER);
      expect(CourseTypes.hyrox.key, CourseTags.HYROX);
      expect(CourseTypes.heyMamma.key, CourseTags.HEY_MAMMA);
    });

    test('ogni tag noto ha una tipologia registrata', () {
      for (final tag in CourseTags.all) {
        expect(CourseTypes.byKey(tag), isNotNull,
            reason: 'tag senza tipologia: $tag');
      }
    });

    test('byKey risolve una tipologia nota', () {
      expect(CourseTypes.byKey(CourseTags.HYROX), CourseTypes.hyrox);
    });

    test('byKey ritorna null per chiave sconosciuta', () {
      expect(CourseTypes.byKey('Sconosciuto'), isNull);
    });

    test('primaryForTags ritorna la prima tipologia riconosciuta', () {
      final type =
          CourseTypes.primaryForTags(['Sconosciuto', CourseTags.HYROX]);
      expect(type, CourseTypes.hyrox);
    });

    test('primaryForTags ritorna null se nessun tag è una tipologia nota', () {
      expect(CourseTypes.primaryForTags(['Sconosciuto']), isNull);
      expect(CourseTypes.primaryForTags(const []), isNull);
    });

    test('primaryForTags rispetta l\'ordine: vince il primo tag noto', () {
      expect(
        CourseTypes.primaryForTags([CourseTags.OPEN, CourseTags.HYROX]),
        CourseTypes.open,
      );
    });

    test('displayName valorizzati, distinti e corretti', () {
      final names = CourseTypes.all.map((t) => t.displayName).toList();
      expect(names.where((n) => n.isEmpty), isEmpty);
      expect(names.toSet().length, names.length);
      expect(CourseTypes.hyrox.displayName, 'Hyrox');
    });

    test('defaultSala, se valorizzata, è una sala valida (invariante duraturo)',
        () {
      for (final type in CourseTypes.all) {
        expect(Sale.isValid(type.defaultSala), true,
            reason:
                'defaultSala non valida per ${type.key}: ${type.defaultSala}');
      }
    });
  });
}
