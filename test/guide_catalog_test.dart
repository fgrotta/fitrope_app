import 'dart:io';

import 'package:fitrope_app/pages/protected/guide/guide_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coerenza fra catalogo, Markdown, immagini generate e `pubspec.yaml`.
///
/// Le immagini le rigenera `scripts/guida_screenshots.sh`: questo test non
/// guarda i pixel, controlla solo che ogni riferimento punti a un file vero e
/// che nessun file resti orfano (una guida che cita un'immagine non
/// dichiarata come asset compila, ma su web mostra un riquadro rotto).
void main() {
  const root = 'assets/guida';
  final imageRef = RegExp(r'!\[[^\]]*\]\((img/[^)\s]+)\)');

  final markdown = {
    for (final entry in guideCatalog)
      entry.id: File('$root/${entry.id}.md').existsSync()
          ? File('$root/${entry.id}.md').readAsStringSync()
          : null,
  };
  final pubspecAssets = File('pubspec.yaml')
      .readAsLinesSync()
      .map((line) => RegExp(r'^\s+-\s+(assets/guida/\S*)').firstMatch(line))
      .whereType<RegExpMatch>()
      .map((m) => m.group(1)!)
      .toSet();

  test('gli id del catalogo sono unici', () {
    final ids = guideCatalog.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('gli id sono in kebab-case, come file, cartelle e scenari', () {
    for (final entry in guideCatalog) {
      expect(entry.id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
  });

  test('ogni voce del catalogo ha il suo .md e il suo scenario', () {
    for (final entry in guideCatalog) {
      expect(markdown[entry.id], isNotNull, reason: '$root/${entry.id}.md');
      expect(entry.asset, '$root/${entry.id}.md');
      expect(File('tool/guida/scenarios/${entry.id}.mjs').existsSync(), isTrue,
          reason: 'tool/guida/scenarios/${entry.id}.mjs');
    }
  });

  test('nessun .md fuori dal catalogo', () {
    final ids = guideCatalog.map((e) => e.id).toSet();
    final files = Directory(root)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.md', ''));
    for (final id in files) {
      expect(ids, contains(id), reason: '$root/$id.md non è nel catalogo');
    }
  });

  test('ogni immagine citata esiste ed è dichiarata in pubspec.yaml', () {
    expect(pubspecAssets, contains('$root/'));
    for (final entry in guideCatalog) {
      for (final match in imageRef.allMatches(markdown[entry.id] ?? '')) {
        final path = match.group(1)!;
        expect(path, startsWith('img/${entry.id}/'),
            reason: '${entry.id}.md cita un\'immagine di un\'altra guida');
        expect(File('$root/$path').existsSync(), isTrue,
            reason: '$root/$path (rigenera con scripts/guida_screenshots.sh)');
        expect(pubspecAssets, contains('$root/img/${entry.id}/'),
            reason: 'manca "- $root/img/${entry.id}/" in pubspec.yaml');
      }
    }
  });

  test('nessuna immagine orfana', () {
    final dir = Directory('$root/img');
    if (!dir.existsSync()) return;
    final cited = {
      for (final text in markdown.values)
        ...imageRef.allMatches(text ?? '').map((m) => '$root/${m.group(1)}'),
    };
    final ids = guideCatalog.map((e) => e.id).toSet();
    for (final sub in dir.listSync().whereType<Directory>()) {
      final id = sub.uri.pathSegments.where((s) => s.isNotEmpty).last;
      expect(ids, contains(id), reason: '${sub.path} non è di nessuna guida');
    }
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      expect(cited, contains(file.path),
          reason: '${file.path} non è citata da nessuna guida');
    }
  });

  test('ogni cartella immagini dichiarata in pubspec.yaml esiste', () {
    for (final asset
        in pubspecAssets.where((a) => a.startsWith('$root/img/'))) {
      expect(Directory(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('guideById trova le voci e ignora gli id sconosciuti', () {
    final first = guideCatalog.first;
    expect(guideById(first.id), same(first));
    expect(guideById('non-esiste'), isNull);
  });
}
