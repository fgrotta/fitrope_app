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
        sala: 'Sala 2',
        googleUrl: _googleUrl,
        icsUrl: _icsUrl,
      );
      expect(body, contains('Pilates'));
      expect(body, contains('Giovedi 10 Aprile 2026'));
      expect(body, contains('09:00 - 10:00'));
      expect(body, contains('Sala 2'));
    });

    test('deve contenere i due bottoni calendario con href escaped', () {
      final body = trialReminderBody(
        courseName: 'Pilates',
        courseDate: 'Giovedi 10 Aprile 2026',
        courseTime: '09:00 - 10:00',
        googleUrl: _googleUrl,
        icsUrl: _icsUrl,
      );
      expect(body, contains('Aggiungi a Google Calendar'));
      expect(body, contains('Apple / Outlook / altro'));
      // Gli & dei query string vanno &amp; dentro l'attributo href.
      expect(
        body,
        contains(
          'href="https://calendar.google.com/calendar/render?action=TEMPLATE&amp;text=Pilates"',
        ),
      );
    });
  });

  group('trialConfirmationSubject', () {
    test('deve contenere il nome del corso e "confermata"', () {
      final subject = trialConfirmationSubject('Pilates Mattina');
      expect(subject, contains('Pilates Mattina'));
      expect(subject, contains('confermata'));
    });
  });

  group('trialConfirmationBody', () {
    test('deve contenere dettagli, sala e bottoni calendario', () {
      final body = trialConfirmationBody(
        courseName: 'Pilates',
        courseDate: 'Giovedi 10 Aprile 2026',
        courseTime: '09:00 - 10:00',
        sala: 'Sala 1',
        googleUrl: _googleUrl,
        icsUrl: _icsUrl,
      );
      expect(body, contains('Iscrizione confermata'));
      expect(body, contains('Giovedi 10 Aprile 2026'));
      expect(body, contains('Sala 1'));
      expect(body, contains('Aggiungi a Google Calendar'));
      expect(body, contains('Apple / Outlook / altro'));
    });

    test('sala vuota: nessuna riga Sala', () {
      final body = trialConfirmationBody(
        courseName: 'Pilates',
        courseDate: 'Giovedi 10 Aprile 2026',
        courseTime: '09:00 - 10:00',
        sala: '   ',
        googleUrl: _googleUrl,
        icsUrl: _icsUrl,
      );
      expect(body, isNot(contains('<strong>Sala:</strong>')));
    });
  });

  group('htmlAttrUrl', () {
    test('trasforma gli & in &amp;', () {
      expect(htmlAttrUrl('https://x/y?a=1&b=2'), 'https://x/y?a=1&amp;b=2');
    });
  });
}

const String _googleUrl =
    'https://calendar.google.com/calendar/render?action=TEMPLATE&text=Pilates';
const String _icsUrl = 'https://example.test/courseIcs?courseId=c1';
