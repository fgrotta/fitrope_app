import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/italian_time.dart';

/// Verifica che l'app ancori orari e date a Europe/Rome (CET/CEST),
/// indipendentemente dal fuso del dispositivo, gestendo l'ora legale.
void main() {
  setUpAll(() => initItalianTime());

  group('toItalianTime (visualizzazione)', () {
    test('estate: UTC+2 (CEST)', () {
      final rome = toItalianTime(DateTime.utc(2026, 7, 1, 12, 0));
      expect(rome.hour, 14); // 12:00 UTC -> 14:00 a Roma
      expect(rome.day, 1);
    });

    test('inverno: UTC+1 (CET)', () {
      final rome = toItalianTime(DateTime.utc(2026, 1, 1, 12, 0));
      expect(rome.hour, 13); // 12:00 UTC -> 13:00 a Roma
    });

    test('cambio giorno: un istante serale UTC resta lo stesso giorno a Roma', () {
      // 1 lug 23:30 a Roma = 21:30 UTC; un device a Tokyo (UTC+9) vedrebbe il 2.
      final rome = toItalianTime(DateTime.utc(2026, 7, 1, 21, 30));
      expect(rome.day, 1);
      expect(rome.hour, 23);
      expect(rome.minute, 30);
    });
  });

  group('italianTimestamp (scrittura)', () {
    test('estate: 19:00 italiane -> 17:00 UTC', () {
      final ts = italianTimestamp(DateTime(2026, 7, 1, 19, 0));
      expect(ts.toDate().toUtc().hour, 17);
    });

    test('inverno: 19:00 italiane -> 18:00 UTC', () {
      final ts = italianTimestamp(DateTime(2026, 1, 1, 19, 0));
      expect(ts.toDate().toUtc().hour, 18);
    });

    test('round-trip: il wall-clock italiano è preservato', () {
      final ts = italianTimestamp(DateTime(2026, 7, 1, 19, 30));
      final back = toItalianTime(ts.toDate());
      expect(back.hour, 19);
      expect(back.minute, 30);
      expect(back.day, 1);
    });

    test('la differenza assoluta (soglia disiscrizione) è indipendente dal fuso', () {
      // Inizio corso 19:00 italiane, "ora" 14:00 italiane dello stesso giorno.
      final start = italianTimestamp(DateTime(2026, 7, 1, 19, 0)).toDate();
      final now = italianTimestamp(DateTime(2026, 7, 1, 14, 0)).toDate();
      expect(start.difference(now).inHours, 5); // sempre 5h, qualunque sia il device
    });
  });
}
