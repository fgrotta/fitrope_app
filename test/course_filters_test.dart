import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Course course({
    required String name,
    required int hour,
    List<String> tags = const [],
    String? sala,
  }) =>
      Course(
        id: name,
        uid: name,
        name: name,
        startDate: Timestamp.fromDate(DateTime(2026, 8, 21, hour)),
        endDate: Timestamp.fromDate(DateTime(2026, 8, 21, hour + 1)),
        capacity: 10,
        subscribed: 0,
        tags: tags,
        sala: sala,
      );

  // Giornata di riferimento: 4 tipologie, entrambe le sale e un corso senza.
  final open1 = course(
      name: 'open1', hour: 9, tags: [CourseTags.OPEN], sala: Sale.SALA_1);
  final open2 = course(
      name: 'open2', hour: 18, tags: [CourseTags.OPEN], sala: Sale.SALA_2);
  final hyroxS2 = course(
      name: 'hyrox-s2', hour: 8, tags: [CourseTags.HYROX], sala: Sale.SALA_2);
  final hyroxS1 = course(
      name: 'hyrox-s1', hour: 14, tags: [CourseTags.HYROX], sala: Sale.SALA_1);
  final pt = course(
      name: 'pt',
      hour: 10,
      tags: [CourseTags.PERSONAL_TRAINER],
      sala: Sale.SALA_1);
  final senzaSala =
      course(name: 'senza-sala', hour: 12, tags: [CourseTags.OPEN]);
  final senzaTag = course(name: 'senza-tag', hour: 7, sala: Sale.SALA_1);

  final giornata = [open1, open2, hyroxS2, hyroxS1, pt, senzaSala, senzaTag];

  List<String> namesOf(List<Course> list) => list.map((c) => c.name).toList();

  group('salaFilterKeyOf', () {
    test('usa il nome della sala quando presente', () {
      expect(salaFilterKeyOf(open1), Sale.SALA_1);
    });

    test('usa la chiave dedicata quando la sala è nulla', () {
      expect(salaFilterKeyOf(senzaSala), kNoSalaFilterKey);
    });

    test('la chiave "senza sala" non collide con una sala valida', () {
      expect(Sale.all, isNot(contains(kNoSalaFilterKey)));
      expect(Sale.isValid(kNoSalaFilterKey), isFalse);
    });
  });

  group('courseTypeKeyOf', () {
    test('risolve la tipologia principale dai tag', () {
      expect(courseTypeKeyOf(hyroxS1), CourseTags.HYROX);
    });

    test('ritorna null per un corso senza tipologia riconosciuta', () {
      expect(courseTypeKeyOf(senzaTag), isNull);
    });
  });

  group('applyCourseFilters', () {
    test('set vuoti significano "tutti"', () {
      expect(applyCourseFilters(giornata, types: {}, sale: {}).length,
          giornata.length);
    });

    test('ordina sempre in ordine cronologico', () {
      expect(
        namesOf(applyCourseFilters(giornata, types: {}, sale: {})),
        [
          'senza-tag',
          'hyrox-s2',
          'open1',
          'pt',
          'senza-sala',
          'hyrox-s1',
          'open2'
        ],
      );
    });

    test('non muta la lista di partenza', () {
      final before = namesOf(giornata);
      applyCourseFilters(giornata, types: {}, sale: {});
      expect(namesOf(giornata), before);
    });

    test('filtra per tipologia', () {
      expect(
        namesOf(
            applyCourseFilters(giornata, types: {CourseTags.HYROX}, sale: {})),
        ['hyrox-s2', 'hyrox-s1'],
      );
    });

    test('la selezione multipla di tipologie è in OR', () {
      expect(
        namesOf(applyCourseFilters(giornata,
            types: {CourseTags.HYROX, CourseTags.PERSONAL_TRAINER}, sale: {})),
        ['hyrox-s2', 'pt', 'hyrox-s1'],
      );
    });

    test('filtra per sala', () {
      expect(
        namesOf(applyCourseFilters(giornata, types: {}, sale: {Sale.SALA_2})),
        ['hyrox-s2', 'open2'],
      );
    });

    test('filtra i corsi senza sala', () {
      expect(
        namesOf(
            applyCourseFilters(giornata, types: {}, sale: {kNoSalaFilterKey})),
        ['senza-sala'],
      );
    });

    test('tipologia e sala si combinano in AND', () {
      expect(
        namesOf(applyCourseFilters(giornata,
            types: {CourseTags.HYROX}, sale: {Sale.SALA_2})),
        ['hyrox-s2'],
      );
    });

    test(
        'un corso senza tipologia riconosciuta è escluso da ogni filtro di tipologia',
        () {
      for (final type in CourseTypes.all) {
        expect(
          namesOf(applyCourseFilters([senzaTag], types: {type.key}, sale: {})),
          isEmpty,
          reason: 'tipologia ${type.key}',
        );
      }
    });

    test('un corso senza tipologia resta visibile con solo il filtro sala', () {
      expect(
        namesOf(applyCourseFilters([senzaTag], types: {}, sale: {Sale.SALA_1})),
        ['senza-tag'],
      );
    });
  });

  group('courseTypeCounts', () {
    test('ha una voce per ogni tipologia registrata, anche a zero', () {
      final counts = courseTypeCounts(giornata, sale: {});
      expect(counts.keys.toSet(), CourseTypes.all.map((t) => t.key).toSet());
      expect(counts[CourseTags.HEY_MAMMA], 0);
    });

    test('conta per tipologia principale, ignorando i corsi senza tipologia',
        () {
      final counts = courseTypeCounts(giornata, sale: {});
      expect(counts[CourseTags.OPEN], 3);
      expect(counts[CourseTags.HYROX], 2);
      expect(counts[CourseTags.PERSONAL_TRAINER], 1);
      // senza-tag non finisce in nessun conteggio
      expect(counts.values.reduce((a, b) => a + b), giornata.length - 1);
    });

    test('applica il filtro Sala: il numero dice cosa vedrei selezionando', () {
      final counts = courseTypeCounts(giornata, sale: {Sale.SALA_2});
      expect(counts[CourseTags.OPEN], 1);
      expect(counts[CourseTags.HYROX], 1);
      expect(counts[CourseTags.PERSONAL_TRAINER], 0);
    });

    test('il conteggio coincide con il risultato del filtro corrispondente',
        () {
      final counts = courseTypeCounts(giornata, sale: {Sale.SALA_1});
      for (final type in CourseTypes.all) {
        expect(
          applyCourseFilters(giornata, types: {type.key}, sale: {Sale.SALA_1})
              .length,
          counts[type.key],
          reason: 'tipologia ${type.key}',
        );
      }
    });
  });

  group('salaCounts', () {
    test('ha una voce per ogni sala più "senza sala"', () {
      final counts = salaCounts(giornata, types: {});
      expect(counts.keys.toSet(), {...Sale.all, kNoSalaFilterKey});
    });

    test('conta tutti i corsi, compresi quelli senza tipologia', () {
      final counts = salaCounts(giornata, types: {});
      expect(counts[Sale.SALA_1], 4); // open1, hyrox-s1, pt, senza-tag
      expect(counts[Sale.SALA_2], 2); // open2, hyrox-s2
      expect(counts[kNoSalaFilterKey], 1); // senza-sala
      expect(counts.values.reduce((a, b) => a + b), giornata.length);
    });

    test('applica il filtro Tipologia', () {
      final counts = salaCounts(giornata, types: {CourseTags.OPEN});
      expect(counts[Sale.SALA_1], 1);
      expect(counts[Sale.SALA_2], 1);
      expect(counts[kNoSalaFilterKey], 1);
    });

    test('il conteggio coincide con il risultato del filtro corrispondente',
        () {
      final types = {CourseTags.HYROX};
      final counts = salaCounts(giornata, types: types);
      for (final key in counts.keys) {
        expect(
          applyCourseFilters(giornata, types: types, sale: {key}).length,
          counts[key],
          reason: 'sala $key',
        );
      }
    });

    test('una sala fuori dalla lista chiusa non crea un chip fantasma', () {
      final legacy = course(name: 'legacy', hour: 6, sala: 'Sala 99');
      final counts = salaCounts([legacy], types: {});
      expect(counts.keys.toSet(), {...Sale.all, kNoSalaFilterKey});
      expect(counts.values.every((v) => v == 0), isTrue);
    });
  });
}
