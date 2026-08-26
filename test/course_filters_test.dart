import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Course course({
    required String name,
    required int hour,
    CourseType type = CourseType.open,
    String? tag,
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
        courseType: type,
        tag: tag,
        courseModelV2: true,
        tags: CourseTags.legacyTagsMirror(type.typeTag, tag),
        sala: sala,
      );

  final open = course(name: 'open', hour: 9, sala: Sale.SALA_1);
  final yoga =
      course(name: 'yoga', hour: 10, tag: CourseTags.YOGA, sala: Sale.SALA_2);
  final hyrox =
      course(name: 'hyrox', hour: 8, tag: CourseTags.HYROX, sala: Sale.SALA_1);
  final pt = course(
      name: 'pt',
      hour: 11,
      type: CourseType.personal_trainer,
      tag: CourseTags.PERSONAL_TRAINER,
      sala: Sale.SALA_1);
  final noSala = course(name: 'no-sala', hour: 12, tag: CourseTags.TABATA);
  final giornata = [open, yoga, hyrox, pt, noSala];

  List<String> names(List<Course> courses) =>
      courses.map((course) => course.name).toList();

  test('chiavi namespaced distinguono tipo e tag', () {
    expect(courseTypeKeyOf(hyrox), typeFilterKey(CourseType.open));
    expect(courseTagKeyOf(hyrox), tagFilterKey(CourseTags.HYROX));
    expect(courseTypeAndTagKeysOf(hyrox), {
      typeFilterKey(CourseType.open),
      tagFilterKey(CourseTags.HYROX),
    });
    expect(courseTagKeyOf(open), kNoTagFilterKey);
  });

  test('filtro tipo Open include anche Hyrox e Yoga', () {
    expect(
      names(applyCourseFilters(
        giornata,
        types: {typeFilterKey(CourseType.open)},
        sale: {},
      )),
      ['hyrox', 'open', 'yoga', 'no-sala'],
    );
  });

  test('filtro tag Hyrox seleziona solo il tag descrittivo', () {
    expect(
      names(applyCourseFilters(
        giornata,
        types: {tagFilterKey(CourseTags.HYROX)},
        sale: {},
      )),
      ['hyrox'],
    );
  });

  test('filtri tipo/tag multipli sono OR, sala si combina in AND', () {
    expect(
      names(applyCourseFilters(
        giornata,
        types: {
          tagFilterKey(CourseTags.YOGA),
          typeFilterKey(CourseType.personal_trainer),
        },
        sale: {Sale.SALA_1},
      )),
      ['pt'],
    );
  });

  test('conteggi fissi includono due tipi, otto tag e senza tag', () {
    final counts = courseTypeCounts(giornata, sale: {});
    expect(counts.length, 11);
    expect(counts[typeFilterKey(CourseType.open)], 4);
    expect(counts[typeFilterKey(CourseType.personal_trainer)], 1);
    expect(counts[tagFilterKey(CourseTags.HYROX)], 1);
    expect(counts[kNoTagFilterKey], 1);
    expect(counts[tagFilterKey(CourseTags.PILATES)], 0);
  });

  test('conteggi di una dimensione applicano gia il filtro dell altra', () {
    final typeCounts = courseTypeCounts(giornata, sale: {Sale.SALA_2});
    expect(typeCounts[typeFilterKey(CourseType.open)], 1);
    expect(typeCounts[tagFilterKey(CourseTags.YOGA)], 1);

    final roomCounts = salaCounts(
      giornata,
      types: {tagFilterKey(CourseTags.HYROX)},
    );
    expect(roomCounts[Sale.SALA_1], 1);
    expect(roomCounts[Sale.SALA_2], 0);
  });

  test('sala null usa la sentinella dedicata', () {
    expect(salaFilterKeyOf(noSala), kNoSalaFilterKey);
  });
}
