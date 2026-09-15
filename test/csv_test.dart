import 'package:fitrope_app/utils/csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Casi replicati da `functions/src/__tests__/migrationCsv.test.ts`: servono a
/// verificare che il port Dart sia un mirror fedele del dialetto server.
void main() {
  group('csvCell', () {
    test('quota i campi che contengono il separatore', () {
      expect(csvCell('riga; con separatore'), '"riga; con separatore"');
    });

    test('raddoppia le virgolette e quota', () {
      expect(csvCell('a"b'), '"a""b"');
    });

    test('quota i campi con newline (LF e CR)', () {
      expect(csvCell('prima\nseconda'), '"prima\nseconda"');
      expect(csvCell('prima\rseconda'), '"prima\rseconda"');
    });

    test('lascia intatto un campo semplice', () {
      expect(csvCell('ok'), 'ok');
    });

    test('null diventa stringa vuota, non "null"', () {
      expect(csvCell(null), '');
    });

    test('preserva gli accenti', () {
      expect(csvCell('Niccolò È'), 'Niccolò È');
    });

    test('serializza le liste in JSON, come il mirror server', () {
      expect(csvCell(['Open', 'Yoga']), '"[""Open"",""Yoga""]"');
    });

    test('numeri e booleani passano da toString', () {
      expect(csvCell(42), '42');
      expect(csvCell(true), 'true');
    });

    group('neutralizzazione formule (divergenza voluta dal mirror)', () {
      test('un telefono con + resta testo', () {
        expect(csvCell('+393331112222'), "'+393331112222");
      });

      test('copre tutti i trigger = + - @', () {
        expect(csvCell('=1+1'), "'=1+1");
        expect(csvCell('-3'), "'-3");
        expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
      });

      test('il campo neutralizzato viene comunque quotato se serve', () {
        expect(csvCell('=a;b'), '"\'=a;b"');
      });

      test('un campo vuoto non viene toccato', () {
        expect(csvCell(''), '');
      });

      test('il trigger a metà campo non fa nulla', () {
        expect(csvCell('a+b'), 'a+b');
      });
    });
  });

  group('csvContent', () {
    test('BOM, intestazione, separatore ; e terminatore CRLF', () {
      final content = csvContent(
        ['plain', 'special'],
        [
          {'plain': 'ok', 'special': 'x'},
        ],
      );

      expect(content.startsWith('\u{FEFF}plain;special\r\n'), isTrue);
      expect(content, endsWith('\r\n'));
      expect(content, contains('ok;x'));
    });

    test('withBom: false omette il BOM (solo per i test)', () {
      final content = csvContent(
        ['a'],
        [
          {'a': '1'},
        ],
        withBom: false,
      );

      expect(content, 'a\r\n1\r\n');
    });

    test('lista vuota di righe → solo header', () {
      expect(csvContent(['a', 'b'], const [], withBom: false), 'a;b\r\n');
    });

    test('una chiave mancante dà cella vuota, non disallinea le colonne', () {
      final content = csvContent(
        ['a', 'b', 'c'],
        [
          {'a': '1', 'c': '3'},
        ],
        withBom: false,
      );

      expect(content, 'a;b;c\r\n1;;3\r\n');
    });

    test('caso composito allineato al test server', () {
      final content = csvContent(
        ['plain', 'special', 'unicode', 'list'],
        [
          {
            'plain': 'ok',
            'special': 'riga; con "virgolette"\ne newline',
            'unicode': 'Giulia È',
            'list': ['Open', 'Yoga'],
          },
        ],
      );

      expect(content, contains('"riga; con ""virgolette""\ne newline"'));
      expect(content, contains('"[""Open"",""Yoga""]"'));
      expect(content, contains('Giulia È'));
    });
  });
}
