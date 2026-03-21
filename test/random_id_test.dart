import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/randomId.dart';

void main() {
  group('randomId', () {
    test('generates a string of length 32', () {
      expect(randomId().length, 32);
    });

    test('only contains alphanumeric characters', () {
      final id = randomId();
      final alphanumeric = RegExp(r'^[A-Za-z0-9]+$');
      expect(alphanumeric.hasMatch(id), true);
    });

    test('generates unique IDs on successive calls', () {
      final ids = List.generate(100, (_) => randomId());
      final unique = ids.toSet();
      expect(unique.length, 100);
    });

    test('never returns an empty string', () {
      for (int i = 0; i < 10; i++) {
        expect(randomId().isNotEmpty, true);
      }
    });
  });
}
