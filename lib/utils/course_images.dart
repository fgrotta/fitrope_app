import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/course.dart';

/// Mappatura delle immagini stock disponibili per ogni tipologia di corso.
/// Le immagini vanno aggiunte in assets/course_images/.
class CourseImages {
  /// Immagine di default generica, usata come fallback quando non c'è
  /// né un'immagine esplicita né una stock per la tipologia.
  static const String defaultImage = 'assets/course_images/default.png';

  static const Map<CourseType, List<String>> imagesByType = {
    CourseType.open: [
      'assets/course_images/open_1.png',
      'assets/course_images/open_2.png',
      'assets/course_images/open_3.png',
    ],
    CourseType.personal_trainer: [
      'assets/course_images/pt_1.png',
      'assets/course_images/pt_2.png',
      'assets/course_images/pt_3.png',
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
  /// Usa imageKey se presente, altrimenti il default per il tipo.
  static String getCourseImage(Course course) {
    if (course.imageKey != null && course.imageKey!.isNotEmpty) {
      return course.imageKey!;
    }
    return getDefaultImage(course.courseType);
  }
}
