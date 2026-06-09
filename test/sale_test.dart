import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Test per la lista chiusa delle sale.
void main() {
  group('Sale', () {
    test('espone esattamente due sale, nell\'ordine atteso', () {
      expect(Sale.all, [Sale.SALA_1, Sale.SALA_2]);
      expect(Sale.all.length, 2);
    });

    test('isValid accetta le sale note', () {
      expect(Sale.isValid(Sale.SALA_1), true);
      expect(Sale.isValid(Sale.SALA_2), true);
    });

    test('isValid accetta null (nessuna sala)', () {
      expect(Sale.isValid(null), true);
    });

    test('isValid rifiuta valori sconosciuti', () {
      expect(Sale.isValid('Sala 3'), false);
      expect(Sale.isValid(''), false);
    });

    test('i valori letterali persistiti su Firestore sono stabili', () {
      // Inchioda le stringhe salvate: un drift romperebbe i dati esistenti.
      expect(Sale.SALA_1, 'Sala 1');
      expect(Sale.SALA_2, 'Sala 2');
    });

    test('isValid è case/space-sensitive e rifiuta le varianti', () {
      expect(Sale.isValid('sala 1'), false);
      expect(Sale.isValid('SALA 1'), false);
      expect(Sale.isValid(' Sala 1'), false);
    });
  });
}
