import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;
FitropeUser user = store.state.user!;

Future<void> subscribeToCourse(String courseId, String userId, {bool force = false}) async {
  QuerySnapshot querySnapshot = await firestore
      .collection('courses')
      .where('uid', isEqualTo: courseId)
      .limit(1)
      .get();

  if (querySnapshot.docs.isEmpty) {
    print('Course $courseId does not exist');
    throw Exception('Course $courseId does not exist');
  }

  DocumentReference courseRef = querySnapshot.docs.first.reference;

  await firestore.runTransaction((transaction) async {
    store.dispatch(StartLoadingAction());
    DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
    int subscribed = courseSnapshot['subscribed'];
    int capacity = courseSnapshot['capacity'];
    
    DocumentReference userRef = firestore.collection('users').doc(userId);
    
    // CORREZIONE: Leggi l'utente DENTRO la transazione per evitare race conditions
    DocumentSnapshot userSnapshot = await transaction.get(userRef);
    List<dynamic> userCourses = userSnapshot['courses'] ?? [];

    // Controlla PRIMA se l'utente è già iscritto
    if (userCourses.contains(courseId)) {
      print('User is already subscribed to this course');
      throw Exception('User is already subscribed to this course');
    }

    // Controlla se l'abbonamento è valido (non scaduto)
    if (userSnapshot['fineIscrizione'] != null) {
      DateTime subscriptionEnd = (userSnapshot['fineIscrizione'] as Timestamp).toDate();
      DateTime courseDate = (courseSnapshot['startDate'] as Timestamp).toDate();
      if (courseDate.isAfter(subscriptionEnd)) {
        throw Exception('Subscription has expired. Cannot subscribe to this course.');
      }
    }
    if (subscribed < capacity || force) {    
      transaction.update(courseRef, {
        'subscribed': subscribed + 1,
    });
    userCourses.add(courseId);
    transaction.update(userRef, {
        'courses': userCourses,
        'entrateDisponibili': userSnapshot['entrateDisponibili'] - 1
      });
    } else {
      throw Exception('Course is full');
    }
  }).then((_) async {
    invalidateUsersCache(); 
    if(user.role != 'Admin' && user.role != 'Trainer') {
      Map<String, dynamic>? userData = await getUserData(userId);
      if (userData != null ) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }
    store.dispatch(FinishLoadingAction());
  }).catchError((error) {
    store.dispatch(FinishLoadingAction());
    print("Failed to subscribe to course: $error");
    throw error;
  });
}
