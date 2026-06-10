import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

// TODO(server-migration): portare updateCourse in Cloud Function (vedi piano
// §11 e PR5/PR6): finché resta client, il lockdown delle rules sui corsi sarà
// solo parziale.
Future<void> updateCourse(Course course, {FirebaseFirestore? firestore}) async {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    // `subscribed` e `waitlist` sono di proprietà del server da PR4 (scritti in
    // transazione dalle callable enrollment): NON vanno riscritti dal modello
    // in memoria, che può essere stale e riporterebbe indietro contatore e
    // lista d'attesa mentre il server processa iscrizioni.
    final data = course.toJson()
      ..remove('subscribed')
      ..remove('waitlist');
    await db.collection('courses').doc(course.uid).update(data);
    invalidateCoursesCache(); // Invalida la cache dopo l'aggiornamento
    print('Course updated ${course.uid} successfully!');
  } catch (e) {
    print('Error updating course: $e');
  }
}
