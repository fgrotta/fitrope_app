import 'dart:convert';
import 'dart:io';

import 'package:fitrope_app/pages/protected/guide/guide_catalog.dart';
import 'package:fitrope_app/pages/protected/guide/guide_index_page.dart';
import 'package:fitrope_app/pages/protected/guide/guide_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bundle finto: il Markdown arriva da una mappa, le immagini non esistono
/// (la pagina deve mostrare il segnaposto, non rompersi).
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files, {this.binary = const {}});

  final Map<String, String> files;
  final Map<String, List<int>> binary;

  @override
  Future<ByteData> load(String key) async {
    final bytes = binary[key];
    if (bytes != null) return ByteData.sublistView(Uint8List.fromList(bytes));
    final text = files[key];
    if (text == null) throw FlutterError('asset mancante: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

const _entry = GuideEntry(
  id: 'prova-guida',
  title: 'Guida di prova',
  summary: 'Un riassunto',
  category: GuideCategory.utenti,
  icon: Icons.help_outline,
);

const _other = GuideEntry(
  id: 'altra-guida',
  title: 'Altra guida',
  summary: 'Un altro riassunto',
  category: GuideCategory.corsi,
  icon: Icons.event,
);

// Il bundle sta SOPRA MaterialApp, come nell'app vera: le route spinte dal
// Navigator (la guida collegata, il dialog di zoom) non sono figlie di `home`.
Widget _app(Widget home, Map<String, String> files) => DefaultAssetBundle(
      bundle: _FakeBundle(files),
      child: MaterialApp(home: home),
    );

void main() {
  const markdown = '# Titolo della guida\n\n'
      'Testo introduttivo.\n\n'
      '![Schermata utenti](img/prova-guida/01-utenti.png)\n\n'
      'Vedi anche [l\'altra guida](guida:altra-guida).\n';

  testWidgets('renderizza titolo, testo e immagine', (tester) async {
    await tester.pumpWidget(_app(
      const GuidePage(entry: _entry, catalog: [_entry, _other]),
      {_entry.asset: markdown},
    ));
    await tester.pumpAndSettle();

    expect(find.text('Guida di prova'), findsOneWidget); // AppBar
    expect(find.text('Titolo della guida'), findsOneWidget);
    expect(find.text('Testo introduttivo.'), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/guida/img/prova-guida/01-utenti.png');
  });

  testWidgets('l\'immagine occupa tutta la larghezza del testo',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Un PNG vero 1280×800, come gli screenshot della guida.
    final png = File('assets/guida/img/abbonamenti/01-assegna-vuota.png')
        .readAsBytesSync();
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _FakeBundle(
        {_entry.asset: markdown},
        binary: {'assets/guida/img/prova-guida/01-utenti.png': png},
      ),
      child: const MaterialApp(
        home: GuidePage(entry: _entry, catalog: [_entry, _other]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 200),
        ));
    await tester.pumpAndSettle();

    final text = tester.getSize(find.text('Testo introduttivo.'));
    final column = tester.getSize(find.byType(MarkdownBody));
    final image = tester.getSize(find.byType(Image));
    expect(text.width, lessThanOrEqualTo(column.width));
    expect(image.width, closeTo(column.width, 1));
  });

  testWidgets('il tap sull\'immagine apre lo zoom', (tester) async {
    await tester.pumpWidget(_app(
      const GuidePage(entry: _entry, catalog: [_entry, _other]),
      {_entry.asset: markdown},
    ));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('un link guida:<id> apre l\'altra guida', (tester) async {
    await tester.pumpWidget(_app(
      const GuidePage(entry: _entry, catalog: [_entry, _other]),
      {
        _entry.asset: markdown,
        _other.asset: '# Seconda\n\nContenuto della seconda.\n',
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('altra guida'));
    await tester.pumpAndSettle();
    expect(find.text('Contenuto della seconda.'), findsOneWidget);
  });

  testWidgets('se il Markdown manca mostra un errore leggibile',
      (tester) async {
    await tester.pumpWidget(_app(
      const GuidePage(entry: _entry, catalog: [_entry]),
      const {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Impossibile caricare la guida'), findsOneWidget);
  });

  group('indice', () {
    testWidgets('elenca le guide per categoria e le filtra per titolo',
        (tester) async {
      await tester.pumpWidget(_app(
        const GuideIndexPage(catalog: [_entry, _other]),
        const {},
      ));
      await tester.pumpAndSettle();

      expect(find.text(GuideCategory.utenti.label), findsOneWidget);
      expect(find.text(GuideCategory.corsi.label), findsOneWidget);
      expect(find.text('Guida di prova'), findsOneWidget);
      expect(find.text('Altra guida'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'altra');
      await tester.pumpAndSettle();
      expect(find.text('Guida di prova'), findsNothing);
      expect(find.text('Altra guida'), findsOneWidget);
      expect(find.text(GuideCategory.utenti.label), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nessuna guida trovata'), findsOneWidget);
    });

    testWidgets('il tap su una voce apre la guida', (tester) async {
      await tester.pumpWidget(_app(
        const GuideIndexPage(catalog: [_entry, _other]),
        {_entry.asset: markdown},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guida di prova'));
      await tester.pumpAndSettle();
      expect(find.text('Titolo della guida'), findsOneWidget);
    });
  });
}
