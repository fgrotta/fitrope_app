import 'package:fitrope_app/types/course_type.dart';

/// Capienza di default per tipologia: un Personal Trainer segue una persona
/// alla volta, i corsi Open hanno la capienza standard di sala.
int defaultCapacityForCourseType(CourseType type) =>
    type == CourseType.personal_trainer ? 1 : 6;
