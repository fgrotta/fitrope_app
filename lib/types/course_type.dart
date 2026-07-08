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

  static CourseType fromString(String? value) {
    if (value == null) return CourseType.open;
    return CourseType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CourseType.open,
    );
  }
}
