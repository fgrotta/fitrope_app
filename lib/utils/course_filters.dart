import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Dimensione su cui agiscono i chip di filtro del calendario.
///
/// I filtri delle due dimensioni restano **entrambi** attivi e si combinano in
/// AND: il selettore cambia soltanto quale gruppo di chip è visibile.
enum CourseFilterDimension { tipologia, sala }

/// Valore con cui si filtrano i corsi senza sala assegnata
/// (`Course.sala == null`). Non è un nome di sala valido, quindi non può
/// collidere con i valori di [Sale].
const String kNoSalaFilterKey = '__senza_sala__';

/// Chiave di filtro "sala" di un corso: il nome della sala, oppure
/// [kNoSalaFilterKey] se il corso non ne ha una.
String salaFilterKeyOf(Course course) => course.sala ?? kNoSalaFilterKey;

/// Chiave della tipologia "principale" del corso, o `null` se nessuno dei suoi
/// tag è una tipologia registrata in [CourseTypes].
String? courseTypeKeyOf(Course course) =>
    CourseTypes.primaryForTags(course.tags)?.key;

/// Un set di filtri vuoto significa "tutti": non filtra nulla.
bool courseMatchesFilters(
  Course course, {
  required Set<String> types,
  required Set<String> sale,
}) {
  if (types.isNotEmpty) {
    final key = courseTypeKeyOf(course);
    // Un corso senza tipologia riconosciuta non corrisponde a nessun filtro
    // di tipologia: meglio non mostrarlo che mostrarlo sotto quella sbagliata.
    if (key == null || !types.contains(key)) return false;
  }
  if (sale.isNotEmpty && !sale.contains(salaFilterKeyOf(course))) return false;
  return true;
}

/// Corsi che superano entrambi i filtri, in ordine cronologico.
List<Course> applyCourseFilters(
  List<Course> courses, {
  required Set<String> types,
  required Set<String> sale,
}) {
  final result = courses
      .where((c) => courseMatchesFilters(c, types: types, sale: sale))
      .toList();
  result.sort((a, b) => a.startDate.compareTo(b.startDate));
  return result;
}

/// Conteggio per ciascun chip "tipologia", con il filtro Sala **già applicato**.
///
/// Il numero risponde a "quanti corsi vedrei selezionando questo chip", non a
/// "quanti corsi di questa tipologia esistono": è ciò che rende prevedibile la
/// combinazione delle due dimensioni. Contiene una voce per ogni tipologia di
/// `CourseTypes.all`, anche a zero, perché i chip sono un set fisso.
Map<String, int> courseTypeCounts(
  List<Course> courses, {
  required Set<String> sale,
}) {
  final counts = <String, int>{
    for (final type in CourseTypes.all) type.key: 0,
  };
  for (final course in courses) {
    if (sale.isNotEmpty && !sale.contains(salaFilterKeyOf(course))) continue;
    final key = courseTypeKeyOf(course);
    if (key != null && counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }
  return counts;
}

/// Conteggio per ciascun chip "sala", con il filtro Tipologia già applicato.
/// Contiene una voce per ogni sala di [Sale] più [kNoSalaFilterKey].
Map<String, int> salaCounts(
  List<Course> courses, {
  required Set<String> types,
}) {
  final counts = <String, int>{
    for (final sala in Sale.all) sala: 0,
    kNoSalaFilterKey: 0,
  };
  for (final course in courses) {
    if (types.isNotEmpty) {
      final key = courseTypeKeyOf(course);
      if (key == null || !types.contains(key)) continue;
    }
    final key = salaFilterKeyOf(course);
    // Una sala fuori dalla lista chiusa (dato legacy) non genera un chip
    // fantasma: viene semplicemente ignorata nei conteggi.
    if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }
  return counts;
}
