import 'dart:math';

import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/get_course_state.dart';

/// Helper di presentazione per il RECUPERO nella giornata.
///
/// La regola autoritativa è nel conteggio (`get_course_state.dart` lato client,
/// `eligibility.ts` lato server): un ingresso perso in una giornata è assorbito,
/// uno a uno, da un'iscrizione attiva della stessa giornata e tipologia. Qui c'è
/// solo quello che serve alla UI per raccontarlo all'utente.

/// Tipologia primaria ai fini della CONTABILITÀ: un corso senza tag riconosciuti
/// è un corso Open, come in `get_course_state.dart` e in `eligibility.ts`.
///
/// NON sostituire con `courseTypeKeyOf` di `course_filters.dart`: quello ritorna
/// `null` per un corso senza tipologia registrata (giusto per filtri e badge,
/// dove inventare un'etichetta sarebbe peggio che ometterla), e usarlo qui
/// renderebbe i corsi senza tag non recuperabili.
String _primaryTag(Course course) =>
    CourseTypes.primaryForTags(course.tags)?.key ?? CourseTags.OPEN;

/// Corsi su cui l'utente può ancora recuperare la lezione se disdice [course]:
/// stessa tipologia primaria (il recupero è per tipologia), stessa giornata, non
/// ancora iniziati, con posti liberi e a cui non è già iscritto.
///
/// L'accesso non viene rivalutato: essere iscritto a [course] implica già
/// l'accesso a quella tipologia.
List<Course> recoveryCandidates(Course course, FitropeUser user,
    {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final String tag = _primaryTag(course);
  final int day = dayKeyMillis(course.startDate.millisecondsSinceEpoch);

  return store.state.allCourses.where((c) {
    if (c.uid == course.uid) return false;
    if (user.courses.contains(c.uid)) return false;
    final int start = c.startDate.millisecondsSinceEpoch;
    if (dayKeyMillis(start) != day) return false;
    if (start <= reference.millisecondsSinceEpoch) return false;
    if (_primaryTag(c) != tag) return false;
    return c.subscribed < c.capacity;
  }).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

/// Lezioni perse oggi e non ancora recuperate, per tipologia primaria.
///
/// Vale per entrambi i tipi di perdita (ingresso o slot settimanale): la regola
/// di assorbimento è la stessa. Chiave = tipologia, valore = quante lezioni
/// restano da recuperare entro la fine della giornata.
Map<String, int> pendingRecoveriesToday(FitropeUser user, {DateTime? now}) {
  final int today =
      dayKeyMillis((now ?? DateTime.now()).millisecondsSinceEpoch);
  final List<Course> allCourses = store.state.allCourses;
  Course? byId(String? id) => allCourses.where((c) => c.uid == id).firstOrNull;

  final Map<String, int> lost = {};
  for (final cancelled in user.cancelledEnrollments) {
    if (!cancelled.entryLost) continue;
    final int start = cancelled.courseStartDate.toDate().millisecondsSinceEpoch;
    if (dayKeyMillis(start) != today) continue;
    // Tipologia non risolvibile → non assorbibile, quindi nemmeno recuperabile.
    final Course? origin = byId(cancelled.courseId);
    if (origin == null) continue;
    final String tag = _primaryTag(origin);
    lost[tag] = (lost[tag] ?? 0) + 1;
  }
  if (lost.isEmpty) return const {};

  final Map<String, int> active = {};
  for (final id in user.courses) {
    final Course? course = byId(id);
    if (course == null) continue;
    final int start = course.startDate.millisecondsSinceEpoch;
    if (dayKeyMillis(start) != today) continue;
    final String tag = _primaryTag(course);
    active[tag] = (active[tag] ?? 0) + 1;
  }

  final Map<String, int> pending = {};
  lost.forEach((tag, count) {
    final int remaining = max(0, count - (active[tag] ?? 0));
    if (remaining > 0) {
      pending[tag] = remaining;
    }
  });
  return pending;
}
