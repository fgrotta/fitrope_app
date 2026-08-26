import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:flutter/material.dart';

/// Identità visiva di una tipologia di corso: un colore e un'icona.
///
/// Serve a distinguere le tipologie a colpo d'occhio nel calendario, ora che
/// non sono più solo Open e Personal Trainer. L'icona accompagna **sempre** il
/// colore: le tonalità delle tipologie convivono nella stessa card con quelle
/// della capienza (vedi `capacityColor`), quindi il colore da solo non è un
/// canale affidabile per distinguerle.
@immutable
class CourseTypeStyle {
  final Color color;
  final IconData icon;

  const CourseTypeStyle({required this.color, required this.icon});
}

/// Stile per tipologia, indicizzato con la stessa `key` di [CourseTypes] (che
/// coincide con il tag in `Course.tags`).
///
/// Tonalità scelte per garantire contrasto WCAG AA (>= 4.5:1) con testo bianco,
/// come già fa `capacityColor`. Nota: per Hyrox si usa orange-700 e non
/// orange-600, che con testo bianco resterebbe sotto la soglia.
const Map<String, CourseTypeStyle> _courseTypeStyles = {
  CourseTags.OPEN: CourseTypeStyle(
    color: Color(0xFF2563EB),
    icon: Icons.groups,
  ),
  CourseTags.PERSONAL_TRAINER: CourseTypeStyle(
    color: Color(0xFF7C3AED),
    icon: Icons.person,
  ),
  CourseTags.HYROX: CourseTypeStyle(color: Color(0xFFC2410C), icon: Icons.bolt),
  CourseTags.YOGA: CourseTypeStyle(
    color: Color(0xFF047857),
    icon: Icons.self_improvement,
  ),
  CourseTags.PILATES: CourseTypeStyle(
    color: Color(0xFFBE185D),
    icon: Icons.accessibility_new,
  ),
  CourseTags.CALISTHENICS: CourseTypeStyle(
    color: Color(0xFF0F766E),
    icon: Icons.sports_gymnastics,
  ),
  CourseTags.POSTURALE: CourseTypeStyle(
    color: Color(0xFF4338CA),
    icon: Icons.airline_seat_recline_normal,
  ),
  CourseTags.TABATA: CourseTypeStyle(
    color: Color(0xFFB91C1C),
    icon: Icons.timer,
  ),
  CourseTags.FITROPE: CourseTypeStyle(
    color: Color(0xFF6D28D9),
    icon: Icons.fitness_center,
  ),
};

/// Stile di ripiego per un corso la cui tipologia non è riconosciuta
/// (slate-500 + icona neutra): non deve mai sembrare una tipologia vera.
const CourseTypeStyle unknownCourseTypeStyle = CourseTypeStyle(
  color: Color(0xFF64748B),
  icon: Icons.fitness_center,
);

/// Stile della tipologia con la [key] indicata, o [unknownCourseTypeStyle].
CourseTypeStyle courseTypeStyleForKey(String? key) => key == null
    ? unknownCourseTypeStyle
    : (_courseTypeStyles[key] ?? unknownCourseTypeStyle);

/// Stile della tipologia "principale" ricavata dai [tags] di un corso
/// (stessa risoluzione di `CourseTypes.primaryForTags`).
CourseTypeStyle courseTypeStyleForTags(List<String> tags) =>
    courseTypeStyleForKey(
      CourseTags.descriptiveTagFromLegacy(tags) ??
          CourseTypes.primaryForTags(tags)?.key,
    );

CourseTypeStyle courseTypeStyleForCourse(Course course) =>
    courseTypeStyleForKey(course.displayTag ?? course.resolvedTypeTag);
