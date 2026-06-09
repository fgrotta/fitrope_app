import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/course.dart';

/// Mappatura delle immagini stock disponibili per ogni tipologia di corso.
/// Le immagini vanno aggiunte in assets/course_images/.
class CourseImages {
  /// Immagine di default generica, usata come fallback quando non c'è
  /// né un'immagine esplicita né una stock per la tipologia.
  static const String defaultImage = 'assets/course_images/default.webp';

  static const Map<CourseType, List<String>> imagesByType = {
    CourseType.open: [
      'assets/course_images/open_1.webp',
      'assets/course_images/open_2.webp',
      'assets/course_images/open_3.webp',
    ],
    CourseType.personal_trainer: [
      'assets/course_images/pt_1.webp',
      'assets/course_images/pt_2.webp',
      'assets/course_images/pt_3.webp',
    ],
  };

  /// Tutte le immagini disponibili (indipendentemente dal tipo)
  static List<String> get all =>
      imagesByType.values.expand((list) => list).toList();

  /// Immagini disponibili per un dato tipo di corso
  static List<String> forType(CourseType type) =>
      imagesByType[type] ?? [];

  /// Immagine di default per un dato tipo di corso.
  /// Se la tipologia non ha immagini stock, usa il default generico.
  static String getDefaultImage(CourseType type) {
    final images = forType(type);
    return images.isNotEmpty ? images.first : defaultImage;
  }

  /// Restituisce il path dell'immagine per un corso.
  /// Usa imageKey solo se è una chiave valida del catalogo, altrimenti
  /// ricade sul default per la tipologia (evita card "vuote" con imageKey stale).
  static String getCourseImage(Course course) {
    final key = course.imageKey;
    if (key != null && key.isNotEmpty && all.contains(key)) {
      return key;
    }
    return getDefaultImage(course.courseType);
  }
}
