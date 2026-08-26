import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';

/// Tipologia di corso (registry in codice).
///
/// La [key] coincide con il type tag del mirror `Course.tags`. Nei documenti
/// V2 il campo autoritativo resta `Course.courseType`; i tag descrittivi non
/// partecipano mai al controllo accessi.
class CourseType {
  final String key;
  final String displayName;

  /// Famiglia di abbonamento che sblocca questa tipologia.
  final SubscriptionFamily family;

  /// Sala di default della tipologia. PREVISTO per il futuro (mappatura
  /// automatica tipologia→sala). Non utilizzato nella v1: la sala si imposta
  /// sul singolo corso.
  final String? defaultSala;

  const CourseType({
    required this.key,
    required this.displayName,
    required this.family,
    this.defaultSala,
  });
}

/// Catalogo delle tipologie di corso disponibili.
///
/// NB: `defaultSala` è volutamente non valorizzato in v1 (scaffolding per la
/// futura mappatura automatica tipologia→sala).
class CourseTypes {
  static const CourseType open = CourseType(
    key: CourseTags.OPEN,
    displayName: 'Open',
    family: SubscriptionFamily.OPEN,
  );
  static const CourseType personalTrainer = CourseType(
    key: CourseTags.PERSONAL_TRAINER,
    displayName: 'Personal Trainer',
    family: SubscriptionFamily.PT,
  );
  static const List<CourseType> all = [open, personalTrainer];

  /// Ritorna la tipologia con la [key] indicata, o `null` se non registrata.
  static CourseType? byKey(String key) {
    for (final type in all) {
      if (type.key == key) return type;
    }
    return null;
  }

  /// Resolver legacy V1. Hyrox e un tag descrittivo Open; Hey Mamma resta un
  /// valore storico speciale e viene gestito dal resolver sul modello Course.
  static CourseType? primaryForTags(List<String> tags) {
    for (final tag in tags) {
      final type = byKey(tag);
      if (type != null) return type;
      if (tag == CourseTags.HYROX) return open;
    }
    return null;
  }
}
