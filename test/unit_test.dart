import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/utils/randomId.dart';

void main() {
  group('Utility Functions Tests', () {
    test('formatDate should format date correctly', () {
      final date = DateTime(2024, 1, 15);
      final formatted = formatDate(date);
      expect(formatted, isA<String>());
      expect(formatted.isNotEmpty, true);
    });

    test('randomId should generate unique IDs', () {
      final id1 = randomId();
      final id2 = randomId();

      expect(id1, isA<String>());
      expect(id2, isA<String>());
      expect(id1.length, greaterThan(0));
      expect(id2.length, greaterThan(0));
      expect(id1, isNot(equals(id2)));
    });
  });
}
