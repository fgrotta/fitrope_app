import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<List<String>> getSubscribers(String courseId) async {
  var usersCollection = FirebaseFirestore.instance.collection('users');
  var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
  return snapshots.docs.map((doc) => "${doc['uid']}").toList();
}

// Funzione per ottenere gli utenti iscritti con i loro dati completi
Future<List<FitropeUser>> getSubscribersWithData(String courseId) async {
  var usersCollection = FirebaseFirestore.instance.collection('users');
  var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
  return snapshots.docs.map((doc) => FitropeUser.fromJson(doc.data())).toList();
}

// Funzione per admin/trainer per cancellare l'iscrizione di un utente specifico (sempre rimborsa il credito)
Future<void> removeUserFromCourse(String courseId, String userId) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('uid', isEqualTo: courseId)
      .limit(1)
      .get();

  if (querySnapshot.docs.isEmpty) {
    throw Exception('Course does not exist');
  }

  DocumentReference courseRef = querySnapshot.docs.first.reference;

  await firestore.runTransaction((transaction) async {
    store.dispatch(StartLoadingAction());
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];

    if (subscribed > 0) {
      
      DocumentReference userRef = firestore.collection('users').doc(userId);

      DocumentSnapshot userSnapshot = await userRef.get();

      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      if (userCourses.contains(courseId)) {
        userCourses.remove(courseId);

        // Per la rimozione da admin/trainer, restituisci sempre il credito se è pacchetto entrate
        String? tipologiaIscrizione = userSnapshot['tipologiaIscrizione'];
        bool isPacchettoEntrate = tipologiaIscrizione == 'PACCHETTO_ENTRATE';
        
        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] + (isPacchettoEntrate ? 1 : 0)
        });
      }
    } else {
      print('No users subscribed to this course');
      throw Exception('No users subscribed to this course');
    }
  }).then((_) async {
    invalidateUsersCache();
    if (store.state.user!.uid == userId) {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }   
    store.dispatch(FinishLoadingAction());
  }).catchError((error) {
    store.dispatch(FinishLoadingAction());
    print("Failed to remove user from course: $error");
    throw error;
  });
}

// Funzione specifica per la disiscrizione forzata da admin (sempre rimborsa il credito)
Future<void> forceUnsubscribeFromCourse(String courseId, String userId) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('uid', isEqualTo: courseId)
      .limit(1)
      .get();

  if (querySnapshot.docs.isEmpty) {
    throw Exception('Course does not exist');
  }

  DocumentReference courseRef = querySnapshot.docs.first.reference;

  await firestore.runTransaction((transaction) async {
    store.dispatch(StartLoadingAction());
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];

    if (subscribed > 0) {
      
      transaction.update(courseRef, {
        'subscribed': subscribed - 1,
      });

      DocumentReference userRef = firestore.collection('users').doc(userId);

      DocumentSnapshot userSnapshot = await userRef.get();

      List<dynamic> userCourses = userSnapshot['courses'] ?? [];

      if (userCourses.contains(courseId)) {
        userCourses.remove(courseId);

        // Per la cancellazione admin, restituisci sempre il credito se è pacchetto entrate
        String? tipologiaIscrizione = userSnapshot['tipologiaIscrizione'];
        bool isPacchettoEntrate = tipologiaIscrizione == 'PACCHETTO_ENTRATE';
        
        transaction.update(userRef, {
          'courses': userCourses,
          'entrateDisponibili': userSnapshot['entrateDisponibili'] + (isPacchettoEntrate ? 1 : 0)
        });
      }
    } else {
      print('No users subscribed to this course');
      throw Exception('No users subscribed to this course');
    }
  }).then((_) async {
    invalidateUsersCache();
    if (store.state.user!.uid == userId) {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }   
    store.dispatch(FinishLoadingAction());
  }).catchError((error) {
    store.dispatch(FinishLoadingAction());
    print("Failed to force unsubscribe: $error");
    throw error;
  });
}

Future<void> deleteCourse(String courseId) async {
  try {
    print('Deleting course $courseId');
    // Prima rimuovi il corso da tutti gli utenti iscritti
    List<String> subscribers = await getSubscribers(courseId);
    // Rimuovi il corso dalla lista corsi di ogni utente iscritto
    for (String userId in subscribers) {
      await forceUnsubscribeFromCourse(courseId, userId);
    }    
    // Poi elimina il corso
    await FirebaseFirestore.instance.collection('courses').doc(courseId).delete();
    invalidateCoursesCache(); // Invalida la cache dopo l'eliminazione
    
    print('Course ${courseId} and all subscriptions deleted successfully!');
  } catch (e) {
    print('Error deleting course: $e');
  }
  
} 