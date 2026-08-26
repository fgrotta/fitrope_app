enum CourseType {
  open,
  personal_trainer;

  String get label {
    switch (this) {
      case CourseType.open:
        return 'Open';
      case CourseType.personal_trainer:
        return 'Personal Trainer';
    }
  }

  String get firestoreValue => name;

  /// Tag di compatibilita usato come primo elemento del mirror legacy
  /// `Course.tags`. Il tipo, non il tag descrittivo, governa l'eligibility.
  String get typeTag {
    switch (this) {
      case CourseType.open:
        return 'Open';
      case CourseType.personal_trainer:
        return 'Personal Trainer';
    }
  }

  /// Parser stretto per i documenti V2. Un valore ignoto non deve mai essere
  /// trasformato implicitamente in Open: renderebbe invisibile un dato corrotto
  /// proprio nel campo autoritativo per l'accesso.
  static CourseType fromString(String? value) {
    if (value == null) {
      throw const FormatException('courseType mancante');
    }
    for (final type in CourseType.values) {
      if (type.name == value) return type;
    }
    throw FormatException('courseType sconosciuto: $value');
  }
}
