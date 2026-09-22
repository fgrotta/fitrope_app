import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
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

/// Filtro con cui il calendario si apre, dedotto da ruolo e abbonamenti.
///
/// Il calendario parte sulla tipologia a cui l'utente ha effettivamente
/// accesso; quando l'accesso è ambiguo — staff, famiglie diverse, nessun
/// abbonamento vivo — non si filtra e si parte da "Tutti" (il set vuoto).
///
/// In ordine:
/// 1. Admin e Trainer vedono tutto: il loro accesso non passa dagli abbonamenti.
/// 2. Abbonamenti **vivi** ([liveSubscriptions]) di una sola famiglia: la
///    tipologia che quella famiglia sblocca ([CourseTypes.forFamily]). Si
///    guardano solo i vivi perché lo snapshot `activeSubscriptions` viene
///    ricalcolato alle scritture, e una voce scaduta non deve continuare a
///    filtrare il calendario. Famiglie diverse insieme: "Tutti".
/// 3. Nessun abbonamento vivo e documento legacy (V1) ancora in corso —
///    prova, abbonamenti temporali, pacchetto entrate: "Open", l'unica
///    tipologia che il modello vecchio sapeva rappresentare. Un documento V2
///    senza abbonamenti vivi è semplicemente scaduto: "Tutti".
///
/// Si applica una volta sola all'apertura della pagina: da lì comanda l'utente.
Set<String> defaultTypeFilterForUser(FitropeUser user, {DateTime? now}) {
  if (user.role == 'Admin' || user.role == 'Trainer') return {};

  final live = liveSubscriptions(user.activeSubscriptions, now: now);
  if (live.isNotEmpty) {
    final families = live.map((s) => s.family).toSet();
    if (families.length != 1) return {};
    final key = CourseTypes.forFamily(families.single)?.key;
    return key == null ? {} : {key};
  }

  // Fallback legacy: ammesso ai soli documenti V1, come in `getCourseState`.
  if (user.subscriptionModelVersion >= 2) return {};
  final fineIscrizione = user.fineIscrizione;
  if (fineIscrizione == null) return {};
  final reference = now ?? DateTime.now();
  if (reference.isAfter(fineIscrizione.toDate())) return {};
  return {CourseTags.OPEN};
}
