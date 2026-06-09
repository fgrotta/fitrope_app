/// Sale della palestra in cui si svolgono i corsi.
///
/// Lista chiusa: per ora esistono solo due sale. La selezione avviene sul
/// singolo corso (vedi `Course.sala`). La mappatura automatica tipologia→sala
/// non è ancora attiva (vedi `CourseType.defaultSala`).
class Sale {
  static const String SALA_1 = 'Sala 1';
  static const String SALA_2 = 'Sala 2';

  /// Tutte le sale selezionabili.
  static const List<String> all = [SALA_1, SALA_2];

  /// `true` se [sala] è un valore valido. `null` (nessuna sala) è ammesso.
  static bool isValid(String? sala) => sala == null || all.contains(sala);
}
