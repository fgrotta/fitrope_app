import 'package:fitrope_app/components/course_image_selector_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const images = [
    'assets/course_images/hyrox_sled_push.webp',
    'assets/course_images/hyrox_sandbag.webp',
  ];

  Future<List<String>> pump(WidgetTester tester, {String? selected}) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseImageSelectorCard(
            images: images,
            selected: selected,
            onSelected: picked.add,
          ),
        ),
      ),
    );
    return picked;
  }

  Finder zoomButton(String path) =>
      find.byKey(ValueKey('course-image-zoom:$path'));
  Finder preview(String path) =>
      find.byKey(ValueKey('course-image-preview:$path'));

  testWidgets('toccare la miniatura seleziona senza aprire l\'anteprima', (
    tester,
  ) async {
    final picked = await pump(tester);

    await tester.tap(find.byKey(ValueKey('course-image-thumb:${images[1]}')));
    await tester.pumpAndSettle();

    expect(picked, [images[1]]);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('la lente apre l\'immagine ingrandita e Chiudi non seleziona', (
    tester,
  ) async {
    final picked = await pump(tester);

    await tester.tap(zoomButton(images[0]));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(preview(images[0]), findsOneWidget);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('dall\'anteprima si può scegliere l\'immagine', (tester) async {
    final picked = await pump(tester);

    await tester.tap(zoomButton(images[1]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usa questa immagine'));
    await tester.pumpAndSettle();

    expect(picked, [images[1]]);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'l\'anteprima dell\'immagine già scelta non ripropone la scelta',
    (tester) async {
      await pump(tester, selected: images[0]);

      await tester.tap(zoomButton(images[0]));
      await tester.pumpAndSettle();

      expect(find.text('Usa questa immagine'), findsNothing);
      expect(find.text('Immagine selezionata'), findsOneWidget);
    },
  );
}
