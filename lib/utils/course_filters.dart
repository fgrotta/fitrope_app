import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';

/// Chiave della tipologia "principale" del corso, o `null` se nessuno dei suoi
/// tag è una tipologia registrata in [CourseTypes].
String? courseTypeKeyOf(Course course) =>
    CourseTypes.primaryForTags(course.tags)?.key;

/// Un set di filtri vuoto significa "tutti": non filtra nulla.
bool courseMatchesFilters(Course course, {required Set<String> types}) {
  if (types.isEmpty) return true;
  final key = courseTypeKeyOf(course);
  // Un corso senza tipologia riconosciuta non corrisponde a nessun filtro
  // di tipologia: meglio non mostrarlo che mostrarlo sotto quella sbagliata.
  return key != null && types.contains(key);
}

/// Corsi che superano il filtro, in ordine cronologico.
List<Course> applyCourseFilters(
  List<Course> courses, {
  required Set<String> types,
}) {
  final result =
      courses.where((c) => courseMatchesFilters(c, types: types)).toList();
  result.sort((a, b) => a.startDate.compareTo(b.startDate));
  return result;
}

/// Conteggio per ciascun chip "tipologia" sui corsi della giornata.
///
/// Il numero risponde a "quanti corsi vedrei selezionando questo chip": è ciò
/// che rende prevedibile il filtro. Contiene una voce per ogni tipologia di
/// `CourseTypes.all`, anche a zero, perché i chip sono un set fisso.
Map<String, int> courseTypeCounts(List<Course> courses) {
  final counts = <String, int>{
    for (final type in CourseTypes.all) type.key: 0,
  };
  for (final course in courses) {
    final key = courseTypeKeyOf(course);
    if (key != null && counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }
  return counts;
}

/// Filtro con cui il calendario si apre, dedotto dagli abbonamenti dell'utente.
///
/// Chi ha **soltanto** abbonamenti PT parte già filtrato su Personal Trainer:
/// è l'unica tipologia a cui può iscriversi, e senza il default dovrebbe
/// restringere a mano a ogni apertura. In ogni altro caso — nessun abbonamento
/// vivo, oppure famiglie diverse — si parte da "Tutti", cioè dal set vuoto.
///
/// Si guarda solo agli abbonamenti **vivi** ([liveSubscriptions]): lo snapshot
/// `activeSubscriptions` viene ricalcolato solo alle scritture, quindi una voce
/// PT scaduta non deve continuare a filtrare il calendario.
Set<String> defaultTypeFilterForSubscriptions(
  List<UserSubscription> subscriptions, {
  DateTime? now,
}) {
  final live = liveSubscriptions(subscriptions, now: now);
  if (live.isEmpty) return {};
  if (live.every((s) => s.family == SubscriptionFamily.PT)) {
    return {CourseTags.PERSONAL_TRAINER};
  }
  return {};
}
