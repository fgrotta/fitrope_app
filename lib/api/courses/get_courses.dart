import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

// Cache per i corsi
List<Course>? _cachedCourses;
DateTime? _lastCacheTime;
const Duration _cacheDuration = Duration(minutes: 1);

// Lettura in corso: `Protected` e `HomePage` chiedono i corsi nello stesso
// frame, e senza de-dup partivano due query identiche.
Future<List<Course>>? _inFlight;
bool _inFlightForced = false;
// Incrementata da ogni invalidazione e da ogni richiesta forzata: una lettura
// partita prima non scrive più la cache (sarebbe più vecchia).
int _generation = 0;

Future<List<Course>> getAllCourses(
    {bool force = false, FirebaseFirestore? firestore}) async {
  // Controlla se la cache è ancora valida
  if (_cachedCourses != null && _lastCacheTime != null && !force) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTime!);
    if (timeSinceLastCache < _cacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedCourses!;
    }
  }

  // Una richiesta normale si aggancia a qualunque lettura in volo; una
  // forzata solo a un'altra forzata, perché quella normale può essere partita
  // prima della mutazione che ha motivato il `force`.
  final inFlight = _inFlight;
  if (inFlight != null && (!force || _inFlightForced)) return inFlight;

  if (force) _generation++;
  final generation = _generation;
  final future =
      _fetchCourses(firestore ?? FirebaseFirestore.instance).then((courses) {
    if (generation == _generation) {
      _cachedCourses = courses;
      _lastCacheTime = DateTime.now();
    }
    return courses;
  });
  _inFlight = future;
  _inFlightForced = force;
  try {
    return await future;
  } finally {
    if (identical(_inFlight, future)) _inFlight = null;
  }
}

Future<List<Course>> _fetchCourses(FirebaseFirestore db) async {
  // Calcola la data di 150 giorni fa
  final cutoffDate = DateTime.now().subtract(const Duration(days: 150));
  final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

  CollectionReference collectionRef = db.collection('courses');
  // Filtra i corsi con startDate successiva alla data di cutoff
  QuerySnapshot querySnapshot = await collectionRef
      .where('startDate', isGreaterThan: cutoffTimestamp)
      .get();

  List<Course> courses = [];

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    try {
      // L'id del documento e' la fonte canonica: i documenti legacy possono
      // non avere id/uid, o contenerne una copia incoerente.
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>)
        ..['id'] = doc.id
        ..['uid'] = doc.id;
      final Course course = Course.fromJson(data);
      courses.add(course);
    } catch (error) {
      // Un record malformato non deve rendere inutilizzabile il calendario.
      // ignore: avoid_print
      print('Corso ${doc.id} non deserializzabile, saltato: $error');
    }
  }

  return courses;
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateCoursesCache() {
  _cachedCourses = null;
  _lastCacheTime = null;
  _generation++;
  _inFlight = null;
}
