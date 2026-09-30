import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/attendance_record.dart';

// Cache delle presenze, stessa forma di get_courses.dart: TTL breve, perché
// durante l'appello i dati cambiano a ogni tocco (e setAttendance la invalida).
const Duration _cacheDuration = Duration(minutes: 1);

class _Cached<T> {
  final T value;
  final DateTime at;
  _Cached(this.value) : at = DateTime.now();
  bool get fresh => DateTime.now().difference(at) < _cacheDuration;
}

final Map<String, _Cached<Map<String, AttendanceRecord>>> _byCourse = {};
final Map<String, _Cached<AttendanceRecord?>> _mine = {};

void invalidateAttendanceCache() {
  _byCourse.clear();
  _mine.clear();
}

/// Presenze di un corso per l'appello, indicizzate per uid. Solo staff: le
/// rules consentono `where courseId ==` ad Admin e Trainer.
Future<Map<String, AttendanceRecord>> getCourseAttendance(
  String courseId, {
  FirebaseFirestore? firestore,
  bool force = false,
}) async {
  final cached = _byCourse[courseId];
  if (!force && cached != null && cached.fresh) return cached.value;

  final db = firestore ?? FirebaseFirestore.instance;
  final snap = await db
      .collection('attendance')
      .where('courseId', isEqualTo: courseId)
      .get();
  final byUser = <String, AttendanceRecord>{
    for (final doc in snap.docs)
      (doc.data()['userId'] as String): AttendanceRecord.fromJson(doc.data()),
  };
  _byCourse[courseId] = _Cached(byUser);
  return byUser;
}

/// Presenza del socio a un corso: get sull'id deterministico (nessun indice),
/// in cache anche quando il doc non esiste. La card la chiede solo se il
/// socio è iscritto e la finestra self è aperta o passata: zero letture sul
/// calendario futuro.
Future<AttendanceRecord?> getMyAttendance(
  String courseId,
  String uid, {
  FirebaseFirestore? firestore,
  bool force = false,
}) async {
  final id = AttendanceRecord.docId(courseId, uid);
  final cached = _mine[id];
  if (!force && cached != null && cached.fresh) return cached.value;

  final db = firestore ?? FirebaseFirestore.instance;
  final snap = await db.collection('attendance').doc(id).get();
  final data = snap.data();
  final record = data == null ? null : AttendanceRecord.fromJson(data);
  _mine[id] = _Cached(record);
  return record;
}
