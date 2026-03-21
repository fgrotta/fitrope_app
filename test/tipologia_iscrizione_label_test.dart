import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';

FitropeUser _user(TipologiaIscrizione? tipo, {int? entrateDisponibili, int? entrateSettimanali}) =>
    FitropeUser(
      uid: 'u1',
      email: 'test@test.com',
      name: 'Mario',
      lastName: 'Rossi',
      courses: [],
      tipologiaIscrizione: tipo,
      entrateDisponibili: entrateDisponibili,
      entrateSettimanali: entrateSettimanali,
      fineIscrizione: Timestamp.fromDate(DateTime(2025, 12, 31)),
      role: 'User',
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  group('getTipologiaIscrizioneLabel', () {
    test('PACCHETTO_ENTRATE returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.PACCHETTO_ENTRATE),
        'Pacchetto Entrate',
      );
    });

    test('ABBONAMENTO_MENSILE returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.ABBONAMENTO_MENSILE),
        'Abbonamento Mensile',
      );
    });

    test('ABBONAMENTO_TRIMESTRALE returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE),
        'Abbonamento Trimestrale',
      );
    });

    test('ABBONAMENTO_SEMESTRALE returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.ABBONAMENTO_SEMESTRALE),
        'Abbonamento Semestrale',
      );
    });

    test('ABBONAMENTO_ANNUALE returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.ABBONAMENTO_ANNUALE),
        'Abbonamento Annuale',
      );
    });

    test('ABBONAMENTO_PROVA returns correct label', () {
      expect(
        getTipologiaIscrizioneLabel(TipologiaIscrizione.ABBONAMENTO_PROVA),
        'Abbonamento di Prova',
      );
    });

    test('null returns "Nessun abbonamento"', () {
      expect(getTipologiaIscrizioneLabel(null), 'Nessun abbonamento');
    });
  });

  group('getTipologiaIscrizioneTitle', () {
    test('ABBONAMENTO_MENSILE not expired returns correct title', () {
      expect(
        getTipologiaIscrizioneTitle(TipologiaIscrizione.ABBONAMENTO_MENSILE, false),
        'Abbonamento mensile',
      );
    });

    test('ABBONAMENTO_MENSILE expired appends (Scaduto)', () {
      expect(
        getTipologiaIscrizioneTitle(TipologiaIscrizione.ABBONAMENTO_MENSILE, true),
        'Abbonamento mensile (Scaduto)',
      );
    });

    test('PACCHETTO_ENTRATE returns correct title', () {
      expect(
        getTipologiaIscrizioneTitle(TipologiaIscrizione.PACCHETTO_ENTRATE, false),
        'Pacchetto entrate',
      );
    });

    test('ABBONAMENTO_PROVA returns correct title', () {
      expect(
        getTipologiaIscrizioneTitle(TipologiaIscrizione.ABBONAMENTO_PROVA, false),
        'Lezione di prova',
      );
    });
  });

  group('getTipologiaIscrizioneDescription', () {
    test('PACCHETTO_ENTRATE includes entrateDisponibili', () {
      final user = _user(TipologiaIscrizione.PACCHETTO_ENTRATE, entrateDisponibili: 8);
      final desc = getTipologiaIscrizioneDescription(user);
      expect(desc, contains('8'));
    });

    test('ABBONAMENTO_MENSILE includes entrateSettimanali', () {
      final user = _user(TipologiaIscrizione.ABBONAMENTO_MENSILE, entrateSettimanali: 3);
      final desc = getTipologiaIscrizioneDescription(user);
      expect(desc, contains('3'));
    });

    test('null tipologiaIscrizione returns empty string', () {
      final user = _user(null);
      expect(getTipologiaIscrizioneDescription(user), '');
    });
  });
}
