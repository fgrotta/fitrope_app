import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/services/email_templates.dart';

/// Test per i template email e la logica di formattazione delle notifiche.
void main() {
  group('waitlistSpotAvailableSubject', () {
    test('deve contenere il nome del corso', () {
      final subject = waitlistSpotAvailableSubject('Pilates Mattina');
      expect(subject, contains('Pilates Mattina'));
    });

    test('deve contenere "Posto disponibile"', () {
      final subject = waitlistSpotAvailableSubject('Yoga');
      expect(subject, contains('Posto disponibile'));
    });
  });

  group('waitlistSpotAvailableBody', () {
    test('deve contenere il nome del corso', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Pilates Mattina',
        courseDate: 'Lunedi 15 Aprile 2026',
        courseTime: '10:00 - 11:00',
        spotsAvailable: 1,
      );
      expect(body, contains('Pilates Mattina'));
    });

    test('deve contenere data e orario', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Corso Test',
        courseDate: 'Martedi 20 Maggio 2026',
        courseTime: '18:30 - 19:30',
        spotsAvailable: 2,
      );
      expect(body, contains('Martedi 20 Maggio 2026'));
      expect(body, contains('18:30 - 19:30'));
    });

    test('deve mostrare "1 posto disponibile" al singolare', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Corso',
        courseDate: 'Data',
        courseTime: 'Ora',
        spotsAvailable: 1,
      );
      expect(body, contains('1 posto disponibile'));
      expect(body, isNot(contains('posti disponibili')));
    });

    test('deve mostrare "N posti disponibili" al plurale', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Corso',
        courseDate: 'Data',
        courseTime: 'Ora',
        spotsAvailable: 3,
      );
      expect(body, contains('3 posti disponibili'));
    });

    test('deve essere HTML valido con struttura base', () {
      final body = waitlistSpotAvailableBody(
        courseName: 'Corso',
        courseDate: 'Data',
        courseTime: 'Ora',
        spotsAvailable: 1,
      );
      expect(body, contains('<html>'));
      expect(body, contains('</html>'));
      expect(body, contains('<body'));
      expect(body, contains('</body>'));
    });
  });

  group('trialReminderSubject', () {
    test('deve contenere il nome del corso', () {
      final subject = trialReminderSubject('Lezione Prova');
      expect(subject, contains('Lezione Prova'));
    });

    test('deve contenere "Promemoria"', () {
      final subject = trialReminderSubject('Corso');
      expect(subject, contains('Promemoria'));
    });
  });

  group('trialReminderBody', () {
    test('deve contenere tutti i parametri', () {
      final body = trialReminderBody(
        courseName: 'Pilates',
        courseDate: 'Giovedi 10 Aprile 2026',
        courseTime: '09:00 - 10:00',
      );
      expect(body, contains('Pilates'));
      expect(body, contains('Giovedi 10 Aprile 2026'));
      expect(body, contains('09:00 - 10:00'));
    });

  });
}
