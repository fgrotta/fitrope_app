/// Primo slot predefinito delle 19:00 strettamente futuro.
///
/// Evita che il form proponga oggi alle 19 dopo che quell'orario è già
/// trascorso, condizione che rendeva una nuova creazione immediatamente
/// invalida.
DateTime nextDefaultCourseStart(
  DateTime now, {
  int hour = 19,
  int minute = 0,
}) {
  var candidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (!candidate.isAfter(now)) {
    candidate = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  return candidate;
}
