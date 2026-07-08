import 'package:flutter/material.dart';

/// Colore della capienza di un corso in base ai POSTI LIBERI:
/// - verde     : >= 50% posti liberi
/// - rosso     : <= 15% posti liberi (incluso pieno)
/// - arancione : negli altri casi
///
/// Tonalità scelte per garantire contrasto WCAG AA (>= 4.5:1) con testo
/// bianco nella pill: verde 5.1:1, arancione 5.0:1, rosso 5.6:1.
Color capacityColor(int subscribed, int capacity) {
  if (capacity <= 0) return const Color(0xFFB45309);
  final freeRatio = (capacity - subscribed) / capacity;
  if (freeRatio <= 0.15) return const Color(0xFFC62828);
  if (freeRatio >= 0.50) return const Color(0xFF2E7D32);
  return const Color(0xFFB45309);
}

/// Etichetta testuale dei posti liberi mostrata nella pill di capienza.
String capacityPillLabel(int subscribed, int capacity) {
  final free = capacity - subscribed;
  if (free <= 0) return 'Pieno';
  if (free == 1) return '1 libero';
  return '$free liberi';
}
