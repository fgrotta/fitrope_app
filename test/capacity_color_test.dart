import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/capacity_color.dart';

/// Test per la regola colore/etichetta della capienza (posti liberi):
/// verde >= 50% liberi, rosso <= 15% liberi o pieno, arancione nel mezzo.
void main() {
  // Tonalità AA-compliant con testo bianco (vedi capacity_color.dart).
  const verde = Color(0xFF2E7D32);
  const rosso = Color(0xFFC62828);
  const arancione = Color(0xFFB45309);

  group('capacityColor', () {
    test('capacity <= 0 -> arancione (guardia divisione per zero)', () {
      expect(capacityColor(0, 0), arancione);
      expect(capacityColor(3, -1), arancione);
    });

    test('soglia 50% liberi inclusiva -> verde', () {
      expect(capacityColor(5, 10), verde); // 50% liberi
      expect(capacityColor(0, 10), verde); // 100% liberi
    });

    test('appena sotto il 50% -> arancione', () {
      expect(capacityColor(6, 10), arancione); // 40% liberi
    });

    test('soglia 15% liberi inclusiva -> rosso', () {
      expect(capacityColor(17, 20), rosso); // 15% liberi
    });

    test('appena sopra il 15% -> arancione', () {
      expect(capacityColor(16, 20), arancione); // 20% liberi
    });

    test('corso pieno -> rosso', () {
      expect(capacityColor(10, 10), rosso); // 0% liberi
    });

    test('over-capacity (freeRatio negativo) -> rosso', () {
      expect(capacityColor(11, 10), rosso);
    });

    test('zona centrale -> arancione', () {
      expect(capacityColor(14, 20), arancione); // 30% liberi
    });
  });

  group('capacityPillLabel', () {
    test('pieno', () {
      expect(capacityPillLabel(10, 10), 'Pieno');
      expect(capacityPillLabel(12, 10), 'Pieno'); // over-capacity
    });

    test('singolare', () {
      expect(capacityPillLabel(9, 10), '1 libero');
    });

    test('plurale', () {
      expect(capacityPillLabel(8, 10), '2 liberi');
      expect(capacityPillLabel(0, 10), '10 liberi');
    });
  });
}
