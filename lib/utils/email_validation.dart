/// Messaggi e normalizzazione condivisi dai flussi di registrazione e admin.
class EmailValidation {
  static const invalidMessage = 'Inserisci un\'email valida';
  static const duplicateProfileMessage =
      'Questa email è già utilizzata. Se è già presente in un profilo Fit House, contatta la palestra.';
  static const duplicateAccountMessage =
      'Questa email è già associata a un account.';

  static String normalize(String value) => value.trim().toLowerCase();

  static bool isValid(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalize(value));

  static String? validate(String? value, {bool optional = false}) {
    final normalized = normalize(value ?? '');
    if (normalized.isEmpty && optional) return null;
    if (!isValid(normalized)) return invalidMessage;
    return null;
  }
}
