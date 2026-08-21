import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/delete_course.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/app_environment.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String _runNamespace = String.fromEnvironment('TEST_RUN_NAMESPACE');

String get testRunNamespace {
  if (isStaging && _runNamespace.trim().isEmpty) {
    throw StateError('TEST_RUN_NAMESPACE è obbligatorio per gli E2E staging.');
  }
  return _runNamespace.trim().isEmpty ? 'local' : _runNamespace.trim();
}

/// Helper per creare/eliminare i CORSI DI TEST direttamente su Firestore.
///
/// I corsi NON sono fixtures statiche: vengono creati al volo durante il test
/// (con namespace del run e date nei successivi 7–14 giorni) e poi eliminati.
///
/// Tutte queste operazioni richiedono di essere autenticati con permessi di
/// scrittura sui corsi (es. login come Admin) prima di chiamarle.

/// Slot alle 18:00 italiane tra otto giorni: abbastanza lontano dalle finestre
/// di disiscrizione, ma sempre dentro la validità delle subscription seed.
({DateTime start, DateTime end}) testCourseSlot({DateTime? now}) {
  final reference = toItalianTime(now ?? DateTime.now());
  final wallClock = DateTime(
    reference.year,
    reference.month,
    reference.day + 8,
    18,
  );
  final start = italianTimestamp(wallClock).toDate();
  final end = start.add(const Duration(hours: 1));
  return (start: start, end: end);
}

/// Animali usati per generare un nome di corso casuale quando non è indicata
/// una tipologia. Servono a distinguere i corsi tra run diversi.
const List<String> _animaliTest = [
  'Leone',
  'Tigre',
  'Pantera',
  'Falco',
  'Lupo',
  'Volpe',
  'Orso',
  'Aquila',
  'Delfino',
  'Gatto',
];

/// Costruisce il nome del corso di test in modo parametrico:
/// - se [tipologia] è indicata → `"Test <tipologia>"` (es. "Test Open")
/// - altrimenti → `"Test <animale random>"` (es. "Test Falco")
///
/// [random] è iniettabile per rendere il nome deterministico nei test.
String buildTestCourseName({String? tipologia, Random? random}) {
  final prefix = '[TEST:$testRunNamespace]';
  if (tipologia != null && tipologia.trim().isNotEmpty) {
    return '$prefix ${tipologia.trim()}';
  }
  final rnd = random ?? Random();
  final unique = DateTime.now().microsecondsSinceEpoch;
  return '$prefix ${_animaliTest[rnd.nextInt(_animaliTest.length)]}-$unique';
}

/// Risolve l'uid di un utente (es. il trainer) a partire dalla sua email,
/// interrogando la collection `users`. Richiede di essere autenticati.
Future<String> resolveUserIdByEmail(String email) async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: email)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) {
    throw StateError('Nessun utente trovato con email "$email"');
  }
  return snap.docs.first.id;
}

/// Restituisce il nome visualizzato ("Nome Cognome") di un utente a partire
/// dalla sua email. Utile per verificare cosa vede l'Admin nella lista iscritti
/// / lista d'attesa (che mostra il nome completo). Richiede di essere autenticati.
Future<String> resolveUserNameByEmail(String email) async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: email)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) {
    throw StateError('Nessun utente trovato con email "$email"');
  }
  final data = snap.docs.first.data();
  return '${data['name'] ?? ''} ${data['lastName'] ?? ''}'.trim();
}

/// Crea un corso di test nello slot dinamico, assegnato al trainer
/// [trainerId]. Ritorna il [Course] creato (con uid generato).
///
/// Il nome è parametrico (vedi [buildTestCourseName]):
/// - se [tipologia] è indicata → `"Test <tipologia>"` e la tipologia diventa
///   anche tag del corso (es. `CourseTags.OPEN`);
/// - altrimenti → `"Test <animale random>"` e nessun tag (corso accessibile a
///   tutti, utile per gli scenari di iscrizione con l'utente base).
///
/// Scriviamo il documento direttamente (non via `createCourse`) per preservare
/// tutti i flag: in particolare [reminderEnabled] di default è FALSE, così il
/// corso di test non fa partire promemoria email/push nello staging.
Future<Course> createTestCourse({
  required String trainerId,
  String? tipologia,
  int capacity = 10,
  int subscribed = 0,
  bool reminderEnabled = false,
  bool waitlistEnabled = true,
  Random? random,
}) async {
  final slot = testCourseSlot();
  final ref = FirebaseFirestore.instance.collection('courses').doc();

  final course = Course(
    id: ref.id, // ignore: deprecated_member_use_from_same_package
    uid: ref.id,
    name: buildTestCourseName(tipologia: tipologia, random: random),
    startDate: Timestamp.fromDate(slot.start),
    endDate: Timestamp.fromDate(slot.end),
    capacity: capacity,
    subscribed: subscribed,
    trainerId: trainerId,
    tags: tipologia != null && tipologia.trim().isNotEmpty
        ? [tipologia.trim()]
        : const [],
    reminderEnabled: reminderEnabled,
    waitlistEnabled: waitlistEnabled,
  );

  await ref.set(course.toJson());
  invalidateCoursesCache();
  return course;
}

/// Elimina un corso di test (rimuove anche iscrizioni/waitlist degli utenti).
/// Da usare in tearDown.
Future<void> deleteTestCourse(String courseId) => deleteCourse(courseId);

/// Cleanup applicativo con una sessione Admin, necessario perché la callable
/// deleteCourse è Admin-only e il test normalmente termina come membro.
Future<void> deleteTestCourseAsAdmin({
  required String courseId,
  required String adminEmail,
  required String adminPassword,
}) async {
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: adminEmail,
    password: adminPassword,
  );
  await deleteTestCourse(courseId);
}
