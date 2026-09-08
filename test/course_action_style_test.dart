import 'package:fitrope_app/components/course_card.dart' show CourseState;
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/course_action_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('courseActionStyleFor', () {
    test('CLOSED non ha pulsante: il corso è passato', () {
      expect(courseActionStyleFor(CourseState.CLOSED), isNull);
    });

    test('CAN_SUBSCRIBE è cliccabile e dice "Prenotati"', () {
      final s = courseActionStyleFor(CourseState.CAN_SUBSCRIBE)!;
      expect(s.label, 'Prenotati');
      expect(s.enabled, isTrue);
      expect(s.background, ghostColor);
      expect(s.foreground, Colors.white);
    });

    test('SUBSCRIBED offre la disiscrizione, in rosso', () {
      final s = courseActionStyleFor(CourseState.SUBSCRIBED)!;
      expect(s.label, 'Rimuovi iscrizione');
      expect(s.enabled, isTrue);
      expect(s.background, dangerColor);
    });

    test('CAN_WAITLIST porta alla lista d\'attesa, in arancione', () {
      final s = courseActionStyleFor(CourseState.CAN_WAITLIST)!;
      expect(s.label, "Lista d'attesa");
      expect(s.enabled, isTrue);
      expect(s.background, Colors.orange);
    });

    test('IN_WAITLIST permette di uscire dalla lista', () {
      final s = courseActionStyleFor(CourseState.IN_WAITLIST)!;
      expect(s.label, "Esci dalla lista d'attesa");
      expect(s.enabled, isTrue);
      expect(s.background, dangerColor);
    });

    test('WAITLIST_SPOT_AVAILABLE invita a iscriversi subito', () {
      final s = courseActionStyleFor(CourseState.WAITLIST_SPOT_AVAILABLE)!;
      expect(s.label, 'Posto disponibile! Iscriviti ora');
      expect(s.enabled, isTrue);
    });

    // Gli stati di blocco: stesso trattamento visivo, testo che spiega il perché.
    // Non sono cliccabili, quindi il colore non deve invitare al tocco.
    test('gli stati bloccanti sono disabilitati e spiegano il motivo', () {
      const attesi = {
        CourseState.NULL: 'Non disponibile',
        CourseState.LIMIT: 'Limite entrate settimanali raggiunto',
        CourseState.FULL: 'Corso pieno',
        CourseState.SUBSCRIBE_LIMIT: 'Entrate disponibili esaurite',
        CourseState.EXPIRED: 'Abbonamento scaduto',
      };
      for (final entry in attesi.entries) {
        final s = courseActionStyleFor(entry.key)!;
        expect(s.label, entry.value, reason: entry.key.name);
        expect(s.enabled, isFalse, reason: entry.key.name);
        expect(s.background, primaryLightColor, reason: entry.key.name);
        expect(s.foreground, onPrimaryColor, reason: entry.key.name);
      }
    });

    test('copre ogni stato di CourseState', () {
      // Se domani si aggiunge uno stato, questo test lo intercetta invece di
      // lasciare un pulsante senza etichetta a runtime.
      for (final st in CourseState.values) {
        if (st == CourseState.CLOSED) continue;
        expect(courseActionStyleFor(st), isNotNull, reason: st.name);
        expect(courseActionStyleFor(st)!.label, isNotEmpty, reason: st.name);
      }
    });
  });
}
