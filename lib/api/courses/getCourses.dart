import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

// Cache per i corsi
List<Course>? _cachedCourses;
DateTime? _lastCacheTime;
const Duration _cacheDuration = Duration(minutes: 1);

Future<List<Course>> getAllCourses({bool force = false}) async {
  // Calcola la data di 45 giorni fa
  final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
  final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

  // Controlla se la cache è ancora valida
  if (_cachedCourses != null && _lastCacheTime != null && !force) {
    final timeSinceLastCache = DateTime.now().difference(_lastCacheTime!);
    if (timeSinceLastCache < _cacheDuration) {
      // Ritorna i dati dalla cache
      return _cachedCourses!;
    }
  }

  CollectionReference collectionRef = FirebaseFirestore.instance.collection('courses');
  // Filtra i corsi con startDate successiva a 45 giorni fa
  QuerySnapshot querySnapshot = await collectionRef
      .where('startDate', isGreaterThan: cutoffTimestamp)
      .get();

  List<Course> courses = [];

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    if((doc.data() as Map<String, dynamic>)['id'] != null) {
      Course course = Course.fromJson(doc.data() as Map<String, dynamic>);
      courses.add(course);
    }
  }

  // Aggiorna la cache
  _cachedCourses = courses;
  _lastCacheTime = DateTime.now();

  return courses;
}

// Funzione per invalidare la cache (utile quando si vuole forzare un refresh)
void invalidateCoursesCache() {
  _cachedCourses = null;
  _lastCacheTime = null;
}