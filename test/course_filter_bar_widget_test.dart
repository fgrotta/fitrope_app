import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_filter_bar.dart';
import 'package:fitrope_app/types/course.dart';
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

  // Hyrox è un tag descrittivo Open nel modello V2 e non genera un chip.
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

  /// Monta la barra con una larghezza realistica di telefono (390 px).
  ///
  /// La `width` pilota **sia** il `MediaQuery` (che è quello che legge
  /// `isDesktop`, e quindi decide fra `Wrap` e riga scrollabile) **sia** il box
  /// che contiene la barra: se i due divergessero il test verificherebbe un
  /// layout che non esiste.
  Future<void> pump(
    WidgetTester tester, {
    List<Course>? courses,
    Set<String>? types,
    void Function(String)? onToggleType,
    VoidCallback? onShowAll,
    double width = 390,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: CourseFilterBar(
                  courses: courses ?? giornata,
                  selectedTypes: types ?? <String>{},
                  onToggleType: onToggleType ?? (_) {},
                  onShowAll: onShowAll ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    // La prima notifica di metrica arriva in un microtask dopo il primo frame:
    // un pump in più fa assestare lo stato dei bordi sfumati.
    await tester.pump();
  }

  bool chipEnabled(WidgetTester tester, String label) =>
      tester
          .widget<FilterChip>(find.byKey(Key('calendar-filter-chip-$label')))
          .onSelected !=
      null;

  Finder horizontalScroll() => find.byWidgetPredicate((w) =>
      w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);

  /// Nella riga scrollabile i chip in coda restano fuori dal viewport: senza
  /// portarli in vista il tap cade nel vuoto, come per un dito che non ha
  /// ancora scrollato.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final finder = find.byKey(Key('calendar-filter-chip-$label'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

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
      await pump(tester, courses: [giornata.first]);
      expect(find.byKey(const Key('calendar-filter-chip-Personal Trainer')),
          findsOneWidget);
      expect(chipEnabled(tester, 'Personal Trainer'), isFalse);
      expect(chipEnabled(tester, 'Open'), isTrue);
    });

    testWidgets(
        'un chip SELEZIONATO a conteggio 0 resta cliccabile (non intrappolato)',
        (tester) async {
      String? toggled;
      await pump(tester,
          courses: [giornata.first],
          types: {CourseTags.PERSONAL_TRAINER},
          onToggleType: (key) => toggled = key);

      expect(chipEnabled(tester, 'Personal Trainer'), isTrue);
      await tapChip(tester, 'Personal Trainer');
      expect(toggled, CourseTags.PERSONAL_TRAINER);
    });

    testWidgets('mostra il conteggio accanto al nome', (tester) async {
      await pump(tester);
      // Open: 3 corsi, incluso Hyrox che è un tag descrittivo.
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-filter-chip-Open')),
          matching: find.textContaining('3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('toccare un chip notifica la chiave della tipologia',
        (tester) async {
      String? toggled;
      await pump(tester, onToggleType: (key) => toggled = key);
      await tapChip(tester, 'Open');
      expect(toggled, CourseTags.OPEN);
    });
  });

  group('CourseFilterBar - chip Tutti', () {
    testWidgets('è il primo chip della barra', (tester) async {
      await pump(tester, width: 1000); // Wrap: tutti i chip sono a schermo
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      expect((chips.first.key as ValueKey<String>?)?.value,
          'calendar-filter-chip-Tutti');
      expect(chips.length, CourseTypes.all.length + 1);
    });

    testWidgets('conta TUTTI i corsi della giornata, anche i senza tipologia',
        (tester) async {
      // Un corso senza tag non finisce in nessun conteggio per tipologia, ma
      // resta una card visibile: "Tutti" deve contarlo.
      final conSenzaTag = [...giornata, course(name: 'boh', hour: 20)];
      await pump(tester, courses: conSenzaTag, width: 1000);
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-filter-chip-Tutti')),
          matching: find.textContaining('${conSenzaTag.length}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('è selezionato quando non c\'è nessun filtro', (tester) async {
      await pump(tester, width: 1000);
      expect(
          tester
              .widget<FilterChip>(
                  find.byKey(const Key('calendar-filter-chip-Tutti')))
              .selected,
          isTrue);
    });

    testWidgets('si deseleziona quando una tipologia è attiva', (tester) async {
      await pump(tester, types: {CourseTags.OPEN}, width: 1000);
      expect(
          tester
              .widget<FilterChip>(
                  find.byKey(const Key('calendar-filter-chip-Tutti')))
              .selected,
          isFalse);
    });

    testWidgets('toccarlo azzera la selezione', (tester) async {
      var shownAll = false;
      await pump(tester,
          types: {CourseTags.OPEN},
          onShowAll: () => shownAll = true,
          width: 1000);
      await tapChip(tester, 'Tutti');
      expect(shownAll, isTrue);
    });

    testWidgets('resta abilitato anche già selezionato (non si intrappola)',
        (tester) async {
      await pump(tester, width: 1000);
      expect(chipEnabled(tester, 'Tutti'), isTrue);
    });
  });

  group('CourseFilterBar - layout', () {
    testWidgets('sotto i 900 px i chip scorrono in orizzontale, senza Wrap',
        (tester) async {
      await pump(tester, width: 390);
      expect(horizontalScroll(), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('da 900 px in su i chip vanno a capo in un Wrap',
        (tester) async {
      await pump(tester, width: 1000);
      expect(find.byType(Wrap), findsOneWidget);
      expect(horizontalScroll(), findsNothing);
    });

    testWidgets('"Tutti" + le tipologie V2 ci sono in entrambe le modalità',
        (tester) async {
      for (final width in [390.0, 1000.0]) {
        await pump(tester, width: width);
        expect(
            find.byType(FilterChip), findsNWidgets(CourseTypes.all.length + 1),
            reason: 'larghezza $width');
      }
    });

    testWidgets('un drag orizzontale muove la posizione di scroll',
        (tester) async {
      await pump(tester, width: 390);
      final scrollable = find.descendant(
        of: horizontalScroll(),
        matching: find.byType(Scrollable),
      );
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(horizontalScroll(), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable).position.pixels,
          greaterThan(before));
    });

    testWidgets('non va in overflow su un tablet stretto (600 px)',
        (tester) async {
      await pump(tester, types: {CourseTags.OPEN}, width: 600);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('la barra non ha un pulsante "Azzera filtri"', (tester) async {
    // Con una dimensione sola si deseleziona toccando il chip; il pulsante
    // resta soltanto nell'empty state del filtro, in CalendarPage.
    await pump(tester, types: {CourseTags.OPEN});
    expect(find.byKey(const Key('calendar-clear-filters')), findsNothing);
    expect(find.text('Azzera filtri'), findsNothing);
  });

  testWidgets('senza corsi la barra non si disegna', (tester) async {
    await pump(tester, courses: []);
    expect(find.byType(FilterChip), findsNothing);
    expect(horizontalScroll(), findsNothing);
  });
}
