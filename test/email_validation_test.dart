import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/email_validation.dart';

void main() {
  group('EmailValidation', () {
    test('normalizza spazi e maiuscole', () {
      expect(EmailValidation.normalize('  Ada@Example.IT '), 'ada@example.it');
    });

    test('valida email richiesta e facoltativa', () {
      expect(EmailValidation.validate(''), EmailValidation.invalidMessage);
      expect(EmailValidation.validate('', optional: true), isNull);
      expect(EmailValidation.validate('ada@example.it'), isNull);
      expect(
        EmailValidation.validate('non-valida'),
        EmailValidation.invalidMessage,
      );
    });

    test('espone messaggio italiano per email già usate', () {
      expect(
        EmailValidation.duplicateProfileMessage,
        contains('contatta la palestra'),
      );
      expect(
        EmailValidation.duplicateAccountMessage,
        contains('già associata'),
      );
    });
  });
}
