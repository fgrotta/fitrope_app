import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_filter_bar.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter/material.dart';
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

  // Giornata senza corsi Hey Mamma: serve a verificare il chip a conteggio 0.
  final giornata = [
    course(name: 'open', hour: 9, tags: [CourseTags.OPEN], sala: Sale.SALA_1),
    course(
        name: 'hyrox', hour: 14, tags: [CourseTags.HYROX], sala: Sale.SALA_2),
    course(
        name: 'pt',
        hour: 10,
        tags: [CourseTags.PERSONAL_TRAINER],
        sala: Sale.SALA_1),
    course(name: 'senza-sala', hour: 18, tags: [CourseTags.OPEN]),
  ];

  /// Monta la barra con una larghezza realistica di telefono (390 px): un
  /// overflow farebbe fallire il test, che è il punto.
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
        body: Center(
          child: SizedBox(
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
      ),
    ));
  }

  bool chipEnabled(WidgetTester tester, String label) =>
      tester
          .widget<FilterChip>(find.byKey(Key('calendar-filter-chip-$label')))
          .onSelected !=
      null;

  group('CourseFilterBar - chip tipologia', () {
    testWidgets('mostra sempre tutte le tipologie di CourseTypes.all',
        (tester) async {
      await pump(tester);
      for (final type in CourseTypes.all) {
        expect(
          find.byKey(Key('calendar-filter-chip-${type.displayName}')),
          findsOneWidget,
          reason: 'chip mancante: ${type.displayName}',
        );
      }
    });

    testWidgets('un chip a conteggio 0 è disabilitato, non nascosto',
        (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('calendar-filter-chip-Hey Mamma')),
          findsOneWidget);
      expect(chipEnabled(tester, 'Hey Mamma'), isFalse);
      expect(chipEnabled(tester, 'Open'), isTrue);
    });

    testWidgets(
        'un chip SELEZIONATO a conteggio 0 resta cliccabile (non intrappolato)',
        (tester) async {
      String? toggled;
      await pump(tester,
          types: {CourseTags.HEY_MAMMA}, onToggleType: (key) => toggled = key);

      expect(chipEnabled(tester, 'Hey Mamma'), isTrue);
      await tester.tap(find.byKey(const Key('calendar-filter-chip-Hey Mamma')));
      expect(toggled, CourseTags.HEY_MAMMA);
    });

    testWidgets('mostra il conteggio accanto al nome', (tester) async {
      await pump(tester);
      // Open: 2 corsi nella giornata di riferimento
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-filter-chip-Open')),
          matching: find.textContaining('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('i conteggi tengono conto del filtro Sala già attivo',
        (tester) async {
      await pump(tester, sale: {Sale.SALA_1});
      // In Sala 1 c'è un solo corso Open, e nessun Hyrox.
      expect(chipEnabled(tester, 'Hyrox'), isFalse);
      expect(chipEnabled(tester, 'Open'), isTrue);
    });

    testWidgets('toccare un chip notifica la chiave della tipologia',
        (tester) async {
      String? toggled;
      await pump(tester, onToggleType: (key) => toggled = key);
      await tester.tap(find.byKey(const Key('calendar-filter-chip-Hyrox')));
      expect(toggled, CourseTags.HYROX);
    });
  });

  group('CourseFilterBar - dimensione Sala', () {
    testWidgets('mostra le sale della lista chiusa più "Senza sala"',
        (tester) async {
      await pump(tester, dimension: CourseFilterDimension.sala);
      for (final sala in Sale.all) {
        expect(find.byKey(Key('calendar-filter-chip-$sala')), findsOneWidget);
      }
      expect(find.byKey(const Key('calendar-filter-chip-Senza sala')),
          findsOneWidget);
      // I chip tipologia non sono più a schermo: una dimensione alla volta.
      expect(find.byKey(const Key('calendar-filter-chip-Open')), findsNothing);
    });

    testWidgets('toccare un chip sala notifica la chiave giusta',
        (tester) async {
      String? toggled;
      await pump(tester,
          dimension: CourseFilterDimension.sala,
          onToggleSala: (key) => toggled = key);
      await tester
          .tap(find.byKey(const Key('calendar-filter-chip-Senza sala')));
      expect(toggled, kNoSalaFilterKey);
    });
  });

  group('CourseFilterBar - selettore di dimensione', () {
    testWidgets('cambia dimensione al tocco', (tester) async {
      CourseFilterDimension? changed;
      await pump(tester, onDimensionChanged: (d) => changed = d);
      await tester.tap(find.text('Sala'));
      expect(changed, CourseFilterDimension.sala);
    });

    testWidgets(
        'il badge segnala i filtri attivi sulla dimensione NON visibile',
        (tester) async {
      // Sala 1 selezionata mentre è visibile la dimensione Tipologia: senza il
      // badge il filtro nascosto restringerebbe la lista senza spiegazione.
      await pump(tester, sale: {Sale.SALA_1});
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-filter-dimension')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('senza filtri attivi non compare nessun badge', (tester) async {
      await pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-filter-dimension')),
          matching: find.text('1'),
        ),
        findsNothing,
      );
    });
  });

  group('CourseFilterBar - azzera filtri', () {
    testWidgets('assente senza filtri attivi', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('calendar-clear-filters')), findsNothing);
    });

    testWidgets('presente e funzionante con un filtro attivo', (tester) async {
      var cleared = false;
      await pump(tester,
          types: {CourseTags.OPEN}, onClear: () => cleared = true);
      await tester.tap(find.byKey(const Key('calendar-clear-filters')));
      expect(cleared, isTrue);
    });
  });

  testWidgets('senza corsi la barra non si disegna', (tester) async {
    await pump(tester, courses: []);
    expect(find.byKey(const Key('calendar-filter-dimension')), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('non va in overflow su un tablet stretto (600 px)',
      (tester) async {
    await pump(tester,
        types: {CourseTags.OPEN}, sale: {Sale.SALA_1}, width: 600);
    expect(tester.takeException(), isNull);
  });
}
