import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/subscription_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kTipologiaIscrizioneOrder', () {
    test('copre esattamente tutte le tipologie dell\'enum', () {
      // Vincola il modulo all'enum: aggiungere una tipologia domani senza
      // ordinarla rompe qui, invece di far sparire silenziosamente una voce
      // dalle distribuzioni della dashboard.
      expect(
        kTipologiaIscrizioneOrder.toSet(),
        equals(TipologiaIscrizione.values.toSet()),
      );
      expect(
        kTipologiaIscrizioneOrder.length,
        TipologiaIscrizione.values.length,
        reason: 'nessun duplicato',
      );
    });

    test('segue l\'ordine di business concordato', () {
      expect(kTipologiaIscrizioneOrder, [
        TipologiaIscrizione.PACCHETTO_ENTRATE,
        TipologiaIscrizione.ABBONAMENTO_PROVA,
        TipologiaIscrizione.ABBONAMENTO_MENSILE,
        TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_SEMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_ANNUALE,
      ]);
    });
  });

  group('orderedTipologiaCounts', () {
    test('include tutte le tipologie anche a conteggio zero', () {
      final result = orderedTipologiaCounts({
        TipologiaIscrizione.ABBONAMENTO_ANNUALE: 3,
      });

      expect(result.map((e) => e.key).toList(), kTipologiaIscrizioneOrder);
      expect(result.map((e) => e.value).toList(), [0, 0, 0, 0, 0, 3]);
    });

    test('mappa vuota → sei voci a zero', () {
      final result = orderedTipologiaCounts(const {});

      expect(result.length, TipologiaIscrizione.values.length);
      expect(result.every((e) => e.value == 0), isTrue);
    });

    test('l\'ordine non dipende dall\'ordine di inserimento nella mappa', () {
      final a = orderedTipologiaCounts({
        TipologiaIscrizione.ABBONAMENTO_MENSILE: 2,
        TipologiaIscrizione.PACCHETTO_ENTRATE: 2,
      });
      final b = orderedTipologiaCounts({
        TipologiaIscrizione.PACCHETTO_ENTRATE: 2,
        TipologiaIscrizione.ABBONAMENTO_MENSILE: 2,
      });

      expect(a.map((e) => e.key).toList(), b.map((e) => e.key).toList());
      expect(a.first.key, TipologiaIscrizione.PACCHETTO_ENTRATE);
    });
  });
}
