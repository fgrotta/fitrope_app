import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/unsubscribeToCourse.dart';

Future<List<String>> getSubscribers(String courseId) async {
  var usersCollection = FirebaseFirestore.instance.collection('users');
  var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
  return snapshots.docs.map((doc) => "${doc['id']}").toList();
}

Future<void> deleteCourse(String courseId) async {
  try {
    // Prima rimuovi il corso da tutti gli utenti iscritti
    final courseDoc = await FirebaseFirestore.instance.collection('courses').doc(courseId).get();
    if (courseDoc.exists) {
      final courseData = courseDoc.data();
      if (courseData != null && courseData['subscribers'] != 0) {
        List<String> subscribers = await getSubscribers(courseId);
        // Rimuovi il corso dalla lista corsi di ogni utente iscritto
        for (String userId in subscribers) {
          unsubscribeToCourse(courseId, userId);
        }
      }
      await FirebaseFirestore.instance.collection('courses').doc(courseId).delete();
    }
    
    // Poi elimina il corso
    print('Course ${courseId} and all subscriptions deleted successfully!');
  } catch (e) {
    print('Error deleting course: $e');
  }
  
} 