import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';

Timestamp _ts(DateTime dt) => Timestamp.fromDate(dt);

void main() {
  group('AbbonamentoHelper', () {
    final now = DateTime.now();

    group('isFineIscrizioneNeiProssimi30Giorni', () {
      test('null scadenza returns false', () {
        expect(AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(null), false);
      });

      test('scadenza in 15 days returns true', () {
        final ref = DateTime(2024, 1, 1);
        final scadenza = _ts(ref.add(const Duration(days: 15)));
        expect(
          AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(scadenza, reference: ref),
          true,
        );
      });

      test('scadenza in exactly 30 days returns false (exclusive upper bound)', () {
        final ref = DateTime(2024, 1, 1);
        final scadenza = _ts(ref.add(const Duration(days: 30)));
        expect(
          AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(scadenza, reference: ref),
          false,
        );
      });

      test('scadenza already expired returns false', () {
        final ref = DateTime(2024, 1, 1);
        final scadenza = _ts(ref.subtract(const Duration(days: 1)));
        expect(
          AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(scadenza, reference: ref),
          false,
        );
      });

      test('scadenza in 29 days returns true', () {
        final ref = DateTime(2024, 1, 1);
        final scadenza = _ts(ref.add(const Duration(days: 29)));
        expect(
          AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(scadenza, reference: ref),
          true,
        );
      });
    });

    group('isAbbonamentoInScadenza', () {
      test('null scadenza returns false', () {
        expect(AbbonamentoHelper.isAbbonamentoInScadenza(null), false);
      });

      test('scadenza already past returns false', () {
        final past = _ts(now.subtract(const Duration(days: 1)));
        expect(AbbonamentoHelper.isAbbonamentoInScadenza(past), false);
      });

      test('scadenza in 10 days returns true (within 15-day threshold)', () {
        final soon = _ts(now.add(const Duration(days: 10)));
        expect(AbbonamentoHelper.isAbbonamentoInScadenza(soon), true);
      });

      test('scadenza in 20 days returns false (beyond 15-day threshold)', () {
        final far = _ts(now.add(const Duration(days: 20)));
        expect(AbbonamentoHelper.isAbbonamentoInScadenza(far), false);
      });
    });

    group('isAbbonamentoScaduto', () {
      test('null scadenza returns false', () {
        expect(AbbonamentoHelper.isAbbonamentoScaduto(null), false);
      });

      test('past scadenza returns true', () {
        final past = _ts(now.subtract(const Duration(days: 1)));
        expect(AbbonamentoHelper.isAbbonamentoScaduto(past), true);
      });

      test('future scadenza returns false', () {
        final future = _ts(now.add(const Duration(days: 30)));
        expect(AbbonamentoHelper.isAbbonamentoScaduto(future), false);
      });
    });

    group('formatDataScadenza', () {
      test('null returns "Non impostato"', () {
        expect(AbbonamentoHelper.formatDataScadenza(null), 'Non impostato');
      });

      test('formats date as dd/MM/yyyy', () {
        final date = _ts(DateTime(2024, 3, 5));
        expect(AbbonamentoHelper.formatDataScadenza(date), '05/03/2024');
      });
    });

    group('getStatoAbbonamento', () {
      test('null returns "Non impostato"', () {
        expect(AbbonamentoHelper.getStatoAbbonamento(null), 'Non impostato');
      });

      test('past scadenza returns "Scaduto"', () {
        final past = _ts(now.subtract(const Duration(days: 5)));
        expect(AbbonamentoHelper.getStatoAbbonamento(past), 'Scaduto');
      });

      test('far future scadenza returns "Valido"', () {
        final future = _ts(now.add(const Duration(days: 60)));
        expect(AbbonamentoHelper.getStatoAbbonamento(future), 'Valido');
      });

      test('near future scadenza returns "Scade tra X giorni"', () {
        final soon = _ts(now.add(const Duration(days: 5)));
        final result = AbbonamentoHelper.getStatoAbbonamento(soon);
        expect(result, startsWith('Scade tra'));
        expect(result, contains('giorni'));
      });
    });

    group('getGiorniRimanenti', () {
      test('null returns -1', () {
        expect(AbbonamentoHelper.getGiorniRimanenti(null), -1);
      });

      test('past date returns negative days', () {
        final past = _ts(now.subtract(const Duration(days: 5)));
        expect(AbbonamentoHelper.getGiorniRimanenti(past), isNegative);
      });

      test('future date returns positive days', () {
        final future = _ts(now.add(const Duration(days: 30)));
        final giorni = AbbonamentoHelper.getGiorniRimanenti(future);
        expect(giorni, greaterThan(0));
        expect(giorni, lessThanOrEqualTo(30));
      });
    });
  });
}
