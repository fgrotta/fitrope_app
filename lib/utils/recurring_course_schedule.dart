/// Genera gli slot di un corso ricorrente nel range inclusivo [start]–[end].
/// Ritorna una lista vuota per range invertiti o senza giorni selezionati.
List<DateTime> calculateRecurringCourseDates({
  required DateTime start,
  required DateTime end,
  required Set<int> weekdays,
}) {
  if (start.isAfter(end) || weekdays.isEmpty) return const [];
  final dates = <DateTime>[];
  var day = DateTime(start.year, start.month, start.day);
  final lastDay = DateTime(end.year, end.month, end.day);
  while (!day.isAfter(lastDay)) {
    if (weekdays.contains(day.weekday)) {
      dates.add(DateTime(
        day.year,
        day.month,
        day.day,
        start.hour,
        start.minute,
      ));
    }
    day = day.add(const Duration(days: 1));
  }
  return dates;
}
