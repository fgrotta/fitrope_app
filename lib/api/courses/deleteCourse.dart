import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/unsubscribeToCourse.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';

Future<List<String>> getSubscribers(String courseId) async {
  var usersCollection = FirebaseFirestore.instance.collection('users');
  var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
  return snapshots.docs.map((doc) => "${doc['uid']}").toList();
}

Future<void> deleteCourse(String courseId) async {
  try {
    print('Deleting course $courseId');
    // Prima rimuovi il corso da tutti gli utenti iscritti
    List<String> subscribers = await getSubscribers(courseId);
    // Rimuovi il corso dalla lista corsi di ogni utente iscritto
    for (String userId in subscribers) {
      await unsubscribeToCourse(courseId, userId);
    }    
    // Poi elimina il corso
    await FirebaseFirestore.instance.collection('courses').doc(courseId).delete();
    invalidateCoursesCache(); // Invalida la cache dopo l'eliminazione
    
    print('Course ${courseId} and all subscriptions deleted successfully!');
  } catch (e) {
    print('Error deleting course: $e');
  }
  
} 