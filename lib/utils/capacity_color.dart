import 'package:flutter/material.dart';

/// Colore della capienza di un corso in base ai POSTI LIBERI:
/// - verde     : >= 50% posti liberi
/// - rosso     : <= 15% posti liberi (incluso pieno)
/// - arancione : negli altri casi
Color capacityColor(int subscribed, int capacity) {
  if (capacity <= 0) return const Color(0xFFFB8C00);
  final freeRatio = (capacity - subscribed) / capacity;
  if (freeRatio <= 0.15) return const Color(0xFFE53935);
  if (freeRatio >= 0.50) return const Color(0xFF43A047);
  return const Color(0xFFFB8C00);
}

/// Etichetta testuale dei posti liberi mostrata nella pill di capienza.
String capacityPillLabel(int subscribed, int capacity) {
  final free = capacity - subscribed;
  if (free <= 0) return 'Pieno';
  if (free == 1) return '1 libero';
  return '$free liberi';
}
