import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';

Timestamp _ts(DateTime dt) => Timestamp.fromDate(dt);

void main() {
  group('CertificatoHelper', () {
    final now = DateTime.now();

    group('isCertificatoInScadenza', () {
      test('null scadenza returns false', () {
        expect(CertificatoHelper.isCertificatoInScadenza(null), false);
      });

      test('already expired returns false', () {
        final past = _ts(now.subtract(const Duration(days: 1)));
        expect(CertificatoHelper.isCertificatoInScadenza(past), false);
      });

      test('scadenza in 10 days returns true (within 15-day threshold)', () {
        final soon = _ts(now.add(const Duration(days: 10)));
        expect(CertificatoHelper.isCertificatoInScadenza(soon), true);
      });

      test('scadenza in 20 days returns false (beyond 15-day threshold)', () {
        final far = _ts(now.add(const Duration(days: 20)));
        expect(CertificatoHelper.isCertificatoInScadenza(far), false);
      });

      test('scadenza today (0 days) returns true', () {
        final today = _ts(now.add(const Duration(hours: 1)));
        expect(CertificatoHelper.isCertificatoInScadenza(today), true);
      });
    });

    group('isCertificatoScaduto', () {
      test('null scadenza returns false', () {
        expect(CertificatoHelper.isCertificatoScaduto(null), false);
      });

      test('past scadenza returns true', () {
        final past = _ts(now.subtract(const Duration(days: 1)));
        expect(CertificatoHelper.isCertificatoScaduto(past), true);
      });

      test('future scadenza returns false', () {
        final future = _ts(now.add(const Duration(days: 365)));
        expect(CertificatoHelper.isCertificatoScaduto(future), false);
      });
    });

    group('formatDataScadenza', () {
      test('null returns "Non impostato"', () {
        expect(CertificatoHelper.formatDataScadenza(null), 'Non impostato');
      });

      test('formats date as dd/MM/yyyy', () {
        final date = _ts(DateTime(2025, 12, 31));
        expect(CertificatoHelper.formatDataScadenza(date), '31/12/2025');
      });
    });

    group('getStatoCertificato', () {
      test('null returns "Non impostato"', () {
        expect(CertificatoHelper.getStatoCertificato(null), 'Non impostato');
      });

      test('past scadenza returns "Scaduto"', () {
        final past = _ts(now.subtract(const Duration(days: 10)));
        expect(CertificatoHelper.getStatoCertificato(past), 'Scaduto');
      });

      test('far future scadenza returns "Valido"', () {
        final future = _ts(now.add(const Duration(days: 60)));
        expect(CertificatoHelper.getStatoCertificato(future), 'Valido');
      });

      test('near future scadenza returns "Scade tra X giorni"', () {
        final soon = _ts(now.add(const Duration(days: 7)));
        final result = CertificatoHelper.getStatoCertificato(soon);
        expect(result, startsWith('Scade tra'));
        expect(result, contains('giorni'));
      });
    });

    group('getGiorniRimanenti', () {
      test('null returns -1', () {
        expect(CertificatoHelper.getGiorniRimanenti(null), -1);
      });

      test('past date returns negative days', () {
        final past = _ts(now.subtract(const Duration(days: 3)));
        expect(CertificatoHelper.getGiorniRimanenti(past), isNegative);
      });

      test('future date returns positive days', () {
        final future = _ts(now.add(const Duration(days: 100)));
        final giorni = CertificatoHelper.getGiorniRimanenti(future);
        expect(giorni, greaterThan(0));
        expect(giorni, lessThanOrEqualTo(100));
      });
    });
  });
}
