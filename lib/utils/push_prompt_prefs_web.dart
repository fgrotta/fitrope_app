import 'package:web/web.dart';

/// Prefisso delle chiavi in `localStorage`. Il valore è l'istante (millis
/// epoch) fino al quale il banner resta nascosto.
const String _keyPrefix = 'fitHouse.pushPrompt.snoozedUntil.';

/// True se il banner [key] è stato chiuso di recente.
///
/// Un valore illeggibile (scritto da una versione vecchia, o manomesso) vale
/// "non in snooze": nel dubbio si mostra il banner, non lo si nasconde per
/// sempre.
bool isPushPromptSnoozed(String key) {
  final raw = window.localStorage.getItem('$_keyPrefix$key');
  if (raw == null) return false;
  final until = int.tryParse(raw);
  if (until == null) return false;
  return DateTime.now().millisecondsSinceEpoch < until;
}

/// Nasconde il banner [key] per [duration].
void snoozePushPrompt(String key, Duration duration) {
  final until = DateTime.now().add(duration).millisecondsSinceEpoch;
  window.localStorage.setItem('$_keyPrefix$key', until.toString());
}
