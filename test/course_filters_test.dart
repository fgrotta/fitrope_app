import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/user_subscription.dart';
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

  // Giornata di riferimento: entrambe le tipologie V2 presenti e un corso
  // senza tag. Hyrox resta un tag descrittivo di un corso Open.
  // La sala resta valorizzata (è ancora un dato della card) ma non filtra più.
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

  group('courseTypeKeyOf', () {
    test('un tag descrittivo Hyrox risolve la tipologia Open', () {
      expect(courseTypeKeyOf(hyroxS1), CourseTags.OPEN);
    });

    test('ritorna null per un corso senza tipologia riconosciuta', () {
      expect(courseTypeKeyOf(senzaTag), isNull);
    });
  });

  group('applyCourseFilters', () {
    test('un set vuoto significa "tutti"', () {
      expect(applyCourseFilters(giornata, types: {}).length, giornata.length);
    });

    test('ordina sempre in ordine cronologico', () {
      expect(
        namesOf(applyCourseFilters(giornata, types: {})),
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
      applyCourseFilters(giornata, types: {});
      expect(namesOf(giornata), before);
    });

    test('filtra per tipologia includendo i tag descrittivi Open', () {
      expect(
        namesOf(applyCourseFilters(giornata, types: {CourseTags.OPEN})),
        ['hyrox-s2', 'open1', 'senza-sala', 'hyrox-s1', 'open2'],
      );
    });

    test('la selezione multipla di tipologie è in OR', () {
      expect(
        namesOf(applyCourseFilters(giornata,
            types: {CourseTags.OPEN, CourseTags.PERSONAL_TRAINER})),
        ['hyrox-s2', 'open1', 'pt', 'senza-sala', 'hyrox-s1', 'open2'],
      );
    });

    test('la sala del corso non influenza il filtro', () {
      // La sala non conta e i due corsi col tag descrittivo Hyrox sono Open.
      expect(
        namesOf(applyCourseFilters(giornata, types: {CourseTags.OPEN})),
        ['hyrox-s2', 'open1', 'senza-sala', 'hyrox-s1', 'open2'],
      );
    });

    test(
        'un corso senza tipologia riconosciuta è escluso da ogni filtro di tipologia',
        () {
      for (final type in CourseTypes.all) {
        expect(
          namesOf(applyCourseFilters([senzaTag], types: {type.key})),
          isEmpty,
          reason: 'tipologia ${type.key}',
        );
      }
    });

    test('un corso senza tipologia resta visibile senza filtri', () {
      expect(namesOf(applyCourseFilters([senzaTag], types: {})), ['senza-tag']);
    });
  });

  group('courseTypeCounts', () {
    test('ha una voce per ogni tipologia registrata, anche a zero', () {
      final counts = courseTypeCounts(giornata);
      expect(counts.keys.toSet(), CourseTypes.all.map((t) => t.key).toSet());
      expect(counts[CourseTags.HEY_MAMMA], isNull);
    });

    test('conta per tipologia principale, ignorando i corsi senza tipologia',
        () {
      final counts = courseTypeCounts(giornata);
      expect(counts[CourseTags.OPEN], 5);
      expect(counts[CourseTags.HYROX], isNull);
      expect(counts[CourseTags.PERSONAL_TRAINER], 1);
      // senza-tag non finisce in nessun conteggio
      expect(counts.values.reduce((a, b) => a + b), giornata.length - 1);
    });

    test('il conteggio coincide con il risultato del filtro corrispondente',
        () {
      final counts = courseTypeCounts(giornata);
      for (final type in CourseTypes.all) {
        expect(
          applyCourseFilters(giornata, types: {type.key}).length,
          counts[type.key],
          reason: 'tipologia ${type.key}',
        );
      }
    });
  });

  group('defaultTypeFilterForSubscriptions', () {
    final now = DateTime(2026, 8, 21, 12);

    UserSubscription sub(SubscriptionFamily family, {int endOffsetDays = 30}) =>
        UserSubscription(
          planKey: '${family.name}-test',
          family: family,
          billingMode: BillingMode.FREQUENCY,
          courseTypeTags: const {},
          startDate: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
          endDate: Timestamp.fromDate(now.add(Duration(days: endOffsetDays))),
        );

    test('senza abbonamenti si parte da "Tutti"', () {
      expect(defaultTypeFilterForSubscriptions([], now: now), isEmpty);
    });

    test('con il solo abbonamento PT si parte filtrato su Personal Trainer',
        () {
      expect(
        defaultTypeFilterForSubscriptions([sub(SubscriptionFamily.PT)],
            now: now),
        {CourseTags.PERSONAL_TRAINER},
      );
    });

    test('più abbonamenti, tutti PT: resta il default PT', () {
      expect(
        defaultTypeFilterForSubscriptions(
            [sub(SubscriptionFamily.PT), sub(SubscriptionFamily.PT)],
            now: now),
        {CourseTags.PERSONAL_TRAINER},
      );
    });

    test('PT insieme a un\'altra famiglia: si parte da "Tutti"', () {
      expect(
        defaultTypeFilterForSubscriptions(
            [sub(SubscriptionFamily.PT), sub(SubscriptionFamily.OPEN)],
            now: now),
        isEmpty,
      );
    });

    test('senza PT si parte da "Tutti"', () {
      expect(
        defaultTypeFilterForSubscriptions([sub(SubscriptionFamily.OPEN)],
            now: now),
        isEmpty,
      );
    });

    test('un PT SCADUTO non filtra: lo snapshot può essere stantio', () {
      expect(
        defaultTypeFilterForSubscriptions(
            [sub(SubscriptionFamily.PT, endOffsetDays: -1)],
            now: now),
        isEmpty,
      );
    });

    test('fra PT vivo e Open scaduto vince il default PT', () {
      expect(
        defaultTypeFilterForSubscriptions([
          sub(SubscriptionFamily.PT),
          sub(SubscriptionFamily.OPEN, endOffsetDays: -3),
        ], now: now),
        {CourseTags.PERSONAL_TRAINER},
      );
    });
  });
}
