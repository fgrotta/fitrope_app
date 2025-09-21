import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

/// Aggiorna il conteggio degli iscritti di un corso nel database
/// Utilizzato per correggere discrepanze tra il numero effettivo di iscritti e il valore salvato
Future<void> updateCourseSubscribedCount(String courseId, int newSubscribedCount) async {
  try {
    // Trova il corso per ID
    QuerySnapshot querySnapshot = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception('Corso non trovato');
    }

    DocumentReference courseRef = querySnapshot.docs.first.reference;
    
    // Aggiorna il conteggio degli iscritti
    await courseRef.update({
      'subscribed': newSubscribedCount,
    });
    invalidateCoursesCache(); // Invalida la cache dopo l'aggiornamento
    print('✅ Conteggio iscritti aggiornato per il corso $courseId: $newSubscribedCount');
    
  } catch (e) {
    print('❌ Errore durante l\'aggiornamento del conteggio iscritti: $e');
    throw Exception('Errore durante l\'aggiornamento: ${e.toString()}');
  }
}
