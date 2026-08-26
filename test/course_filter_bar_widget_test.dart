import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_filter_bar.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter/material.dart';
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

  final giornata = [
    course(name: 'open', hour: 9, sala: Sale.SALA_1),
    course(name: 'hyrox', hour: 14, tag: CourseTags.HYROX, sala: Sale.SALA_2),
    course(
        name: 'pt',
        hour: 10,
        type: CourseType.personal_trainer,
        tag: CourseTags.PERSONAL_TRAINER,
        sala: Sale.SALA_1),
    course(name: 'senza-sala', hour: 18),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<Course>? courses,
    Set<String>? types,
    Set<String>? sale,
    CourseFilterDimension dimension = CourseFilterDimension.tipologia,
    void Function(String)? onToggleType,
    void Function(String)? onToggleSala,
    void Function(CourseFilterDimension)? onDimensionChanged,
    VoidCallback? onClear,
    double width = 390,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: CourseFilterBar(
              courses: courses ?? giornata,
              selectedTypes: types ?? <String>{},
              selectedSale: sale ?? <String>{},
              dimension: dimension,
              onDimensionChanged: onDimensionChanged ?? (_) {},
              onToggleType: onToggleType ?? (_) {},
              onToggleSala: onToggleSala ?? (_) {},
              onClearFilters: onClear ?? () {},
            ),
          ),
        ),
      ),
    ));
  }

  Finder chip(String key) => find.byKey(Key('calendar-filter-chip-$key'));
  bool chipEnabled(WidgetTester tester, String key) =>
      tester.widget<FilterChip>(chip(key)).onSelected != null;

  testWidgets('mostra sempre i due tipi, gli otto tag e senza tag',
      (tester) async {
    await pump(tester);
    for (final type in CourseType.values) {
      expect(chip(typeFilterKey(type)), findsOneWidget);
    }
    for (final tag in CourseTags.selectable) {
      expect(chip(tagFilterKey(tag)), findsOneWidget);
    }
    expect(chip(kNoTagFilterKey), findsOneWidget);
  });

  testWidgets(
      'un chip a zero e disabilitato ma se selezionato resta cliccabile',
      (tester) async {
    final key = tagFilterKey(CourseTags.PILATES);
    await pump(tester);
    expect(chipEnabled(tester, key), isFalse);

    String? toggled;
    await pump(tester, types: {key}, onToggleType: (value) => toggled = value);
    expect(chipEnabled(tester, key), isTrue);
    await tester.tap(chip(key));
    expect(toggled, key);
  });

  testWidgets('conteggi applicano il filtro sala e il tap notifica la chiave',
      (tester) async {
    String? toggled;
    final hyroxKey = tagFilterKey(CourseTags.HYROX);
    await pump(tester,
        sale: {Sale.SALA_1}, onToggleType: (value) => toggled = value);
    expect(chipEnabled(tester, hyroxKey), isFalse);
    expect(chipEnabled(tester, typeFilterKey(CourseType.open)), isTrue);

    await pump(tester, onToggleType: (value) => toggled = value);
    await tester.tap(chip(hyroxKey));
    expect(toggled, hyroxKey);
  });

  testWidgets('dimensione sala usa chiavi stabili', (tester) async {
    String? toggled;
    await pump(tester,
        dimension: CourseFilterDimension.sala,
        onToggleSala: (value) => toggled = value);
    for (final sala in Sale.all) {
      expect(chip(sala), findsOneWidget);
    }
    expect(chip(kNoSalaFilterKey), findsOneWidget);
    await tester.tap(chip(kNoSalaFilterKey));
    expect(toggled, kNoSalaFilterKey);
  });

  testWidgets('selettore, badge e azzera filtri funzionano', (tester) async {
    CourseFilterDimension? changed;
    var cleared = false;
    await pump(tester,
        sale: {Sale.SALA_1},
        onDimensionChanged: (value) => changed = value,
        onClear: () => cleared = true);
    await tester.tap(find.text('Sala'));
    expect(changed, CourseFilterDimension.sala);
    expect(find.byKey(const Key('calendar-clear-filters')), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-clear-filters')));
    expect(cleared, true);
  });

  testWidgets('senza corsi non si disegna e a 600px non va in overflow',
      (tester) async {
    await pump(tester, courses: []);
    expect(find.byKey(const Key('calendar-filter-dimension')), findsNothing);

    await pump(tester,
        types: {typeFilterKey(CourseType.open)},
        sale: {Sale.SALA_1},
        width: 600);
    expect(tester.takeException(), isNull);
  });
}
