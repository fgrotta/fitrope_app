import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:fitrope_app/utils/subscription_dates.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultEndDate', () {
    test('piano a mesi: stesso giorno N mesi dopo', () {
      final plan = SubscriptionPlans.byKey('open_2x_3m')!;
      expect(defaultEndDate(plan, DateTime(2026, 10, 1)), DateTime(2027, 1, 1));
    });

    test('fine mese: 31 gennaio + 1 mese = 28 febbraio', () {
      final plan = SubscriptionPlans.byKey('open_2x_1m')!;
      expect(
          defaultEndDate(plan, DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
      expect(
          defaultEndDate(plan, DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    });

    test('piano a giorni (Prova): +30 giorni', () {
      expect(
        defaultEndDate(SubscriptionPlans.trial, DateTime(2026, 10, 1)),
        DateTime(2026, 10, 31),
      );
    });

    test('ignora l\'ora del giorno di inizio', () {
      final plan = SubscriptionPlans.byKey('open_2x_1m')!;
      expect(
        defaultEndDate(plan, DateTime(2026, 3, 10, 18, 30)),
        DateTime(2026, 4, 10),
      );
    });
  });

  group('finestra in orario di Roma', () {
    test('inizio alle 00:00 e fine alle 23:59:59.999 di Roma', () {
      final start = subscriptionStartTimestamp(DateTime(2026, 10, 1));
      final end = subscriptionEndTimestamp(DateTime(2026, 10, 31));
      final s = toItalianTime(start.toDate());
      final e = toItalianTime(end.toDate());
      expect([s.year, s.month, s.day, s.hour, s.minute], [2026, 10, 1, 0, 0]);
      expect(
        [e.year, e.month, e.day, e.hour, e.minute, e.second, e.millisecond],
        [2026, 10, 31, 23, 59, 59, 999],
      );
    });

    test('romeDay riporta un Timestamp al giorno di Roma', () {
      // 31 ottobre 23:30 UTC = 1 novembre 00:30 a Roma (CET).
      final ts = Timestamp.fromDate(DateTime.utc(2026, 10, 31, 23, 30));
      expect(romeDay(ts), DateTime(2026, 11, 1));
    });
  });
}
