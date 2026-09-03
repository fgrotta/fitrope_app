import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/is_demo_lesson_user.dart';

FitropeUser buildUser({
  TipologiaIscrizione? tipologia,
  bool isActive = true,
}) {
  return FitropeUser(
    uid: 'u1',
    email: 'mario@example.it',
    name: 'Mario',
    lastName: 'Rossi',
    courses: const [],
    tipologiaIscrizione: tipologia,
    entrateDisponibili: 1,
    entrateSettimanali: 0,
    fineIscrizione: null,
    role: 'User',
    isActive: isActive,
    createdAt: DateTime(2026, 9, 1),
  );
}

void main() {
  group('isDemoLessonUser', () {
    test('è vero per un utente PROVA attivo', () {
      expect(
        isDemoLessonUser(
          buildUser(tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA),
        ),
        isTrue,
      );
    });

    test('è falso per un utente PROVA disattivato', () {
      expect(
        isDemoLessonUser(
          buildUser(
            tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
            isActive: false,
          ),
        ),
        isFalse,
      );
    });

    test('è falso per un abbonamento non di prova', () {
      for (final t in [
        TipologiaIscrizione.ABBONAMENTO_MENSILE,
        TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_SEMESTRALE,
        TipologiaIscrizione.ABBONAMENTO_ANNUALE,
        TipologiaIscrizione.PACCHETTO_ENTRATE,
      ]) {
        expect(isDemoLessonUser(buildUser(tipologia: t)), isFalse, reason: '$t');
      }
    });

    test('è falso se la tipologia non è impostata', () {
      expect(isDemoLessonUser(buildUser()), isFalse);
    });
  });
}
