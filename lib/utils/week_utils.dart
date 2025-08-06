class WeekUtils {
  /// Genera la chiave della settimana nel formato "YYYY-WW"
  static String getWeekKey(DateTime date) {
    // Calcola l'inizio della settimana (lunedì)
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    
    // Calcola il numero della settimana nell'anno
    DateTime firstDayOfYear = DateTime(date.year, 1, 1);
    int daysSinceFirstDay = startOfWeek.difference(firstDayOfYear).inDays;
    int weekNumber = ((daysSinceFirstDay + firstDayOfYear.weekday - 1) / 7).floor() + 1;
    
    return "${date.year}-${weekNumber.toString().padLeft(2, '0')}";
  }

  /// Ottiene l'inizio e la fine della settimana per una data specifica
  static Map<String, DateTime> getWeekRange(DateTime date) {
    DateTime startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    startOfWeek = DateTime.utc(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
    
    return {
      'start': startOfWeek,
      'end': endOfWeek,
    };
  }

  /// Controlla se una data è all'interno di una settimana specifica
  static bool isDateInWeek(DateTime date, String weekKey) {
    String dateWeekKey = getWeekKey(date);
    return dateWeekKey == weekKey;
  }

  /// Calcola il numero di disdette tardive per una settimana specifica
  static int getDisdetteTardiveForWeek(Map<String, int>? disdetteTardiveSettimanali, String weekKey) {
    if (disdetteTardiveSettimanali == null) return 0;
    return disdetteTardiveSettimanali[weekKey] ?? 0;
  }

  /// Incrementa il contatore delle disdette tardive per una settimana
  static Map<String, int> incrementDisdetteTardive(Map<String, int>? currentDisdette, String weekKey) {
    Map<String, int> newDisdette = Map<String, int>.from(currentDisdette ?? {});
    newDisdette[weekKey] = (newDisdette[weekKey] ?? 0) + 1;
    return newDisdette;
  }
} 