import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/formatDate.dart';

void main() {
  group('formatDate', () {
    test('returns empty string for null', () {
      expect(formatDate(null), '');
    });

    test('formats a basic date correctly', () {
      expect(formatDate(DateTime(2024, 3, 15)), '15 Marzo 2024');
    });

    test('formats all 12 months correctly', () {
      final months = [
        'Gennaio', 'Febbraio', 'Marzo', 'Aprile',
        'Maggio', 'Giugno', 'Luglio', 'Agosto',
        'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
      ];
      for (int i = 0; i < 12; i++) {
        expect(formatDate(DateTime(2024, i + 1, 1)), '1 ${months[i]} 2024');
      }
    });

    test('formats day 1 without leading zero', () {
      expect(formatDate(DateTime(2024, 5, 1)), '1 Maggio 2024');
    });

    test('formats day 31 correctly', () {
      expect(formatDate(DateTime(2024, 1, 31)), '31 Gennaio 2024');
    });

    test('formats leap day correctly', () {
      expect(formatDate(DateTime(2024, 2, 29)), '29 Febbraio 2024');
    });
  });
}
