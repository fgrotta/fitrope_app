import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Valida i campi di selezione comuni ai form dei corsi.
///
/// I controlli seguono l'ordine dei campi mostrati nell'interfaccia.
String? validateCourseSelections({
  required String name,
  required String? tag,
  required String? trainerId,
  required String? sala,
  required int capacity,
}) {
  if (name.trim().isEmpty) return 'Il nome del corso è obbligatorio';
  if (!CourseTags.isSelectable(tag)) return 'Seleziona un tag per il corso';
  if (trainerId == null || trainerId.isEmpty) return 'Seleziona un trainer';
  if (sala == null || !Sale.isValid(sala)) return 'Seleziona una sala';
  if (capacity <= 0) {
    return 'Il numero di partecipanti deve essere maggiore di 0';
  }
  return null;
}
