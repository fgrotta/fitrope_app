import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';

/// Tipologia di corso (registry in codice).
///
/// La [key] coincide con il tag usato in `Course.tags` e in
/// `FitropeUser.tipologiaCorsoTags`: così il controllo accessi esistente
/// (`CourseTags.canUserAccessCourse`) resta invariato e non serve alcuna
/// migrazione dei corsi.
class CourseType {
  final String key;
  final String displayName;

  /// Famiglia di abbonamento che sblocca questa tipologia (null = nessun
  /// abbonamento dedicato, es. Hey Mamma).
  final SubscriptionFamily? family;

  /// Sala di default della tipologia. PREVISTO per il futuro (mappatura
  /// automatica tipologia→sala). Non utilizzato nella v1: la sala si imposta
  /// sul singolo corso.
  final String? defaultSala;

  const CourseType({
    required this.key,
    required this.displayName,
    this.family,
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
  static const CourseType hyrox = CourseType(
    key: CourseTags.HYROX,
    displayName: 'Hyrox',
    family: SubscriptionFamily.HYROX,
  );
  static const CourseType heyMamma = CourseType(
    key: CourseTags.HEY_MAMMA,
    displayName: 'Hey Mamma',
  );

  static const List<CourseType> all = [open, personalTrainer, hyrox, heyMamma];

  /// Ritorna la tipologia con la [key] indicata, o `null` se non registrata.
  static CourseType? byKey(String key) {
    for (final type in all) {
      if (type.key == key) return type;
    }
    return null;
  }

  /// Risolve la tipologia "principale" di un corso a partire dai suoi [tags]
  /// (primo tag riconosciuto). Ritorna `null` se nessun tag è una tipologia nota.
  static CourseType? primaryForTags(List<String> tags) {
    for (final tag in tags) {
      final type = byKey(tag);
      if (type != null) return type;
    }
    return null;
  }
}
