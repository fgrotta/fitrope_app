import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/week_utils.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> unsubscribeToCourse(String courseId, String userId, {bool userConfirmed = false}) async {
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

      DateTime startDate = courseSnapshot['startDate'].toDate();
      DateTime now = DateTime.now();

      Duration difference = startDate.difference(now);
      int hoursDifference = difference.inHours;

      // Controlla il tipo di abbonamento dell'utente
      String? tipologiaIscrizione = userSnapshot['tipologiaIscrizione'];
      bool isPacchettoEntrate = tipologiaIscrizione == 'PACCHETTO_ENTRATE';
      bool isAbbonamentoConLimiti = tipologiaIscrizione == 'ABBONAMENTO_TRIMESTRALE' || 
                                   tipologiaIscrizione == 'ABBONAMENTO_SEMESTRALE' || 
                                   tipologiaIscrizione == 'ABBONAMENTO_ANNUALE';
      
      // Per il pacchetto entrate, controlla se la disiscrizione è nelle 8 ore precedenti
      bool shouldRefund = true;
      if (isPacchettoEntrate && hoursDifference <= 8) {
        if (!userConfirmed) {
          throw Exception('CONFIRMATION_REQUIRED');
        }
        shouldRefund = false;
      }

      // Per gli abbonamenti con limiti settimanali, gestisci le disdette tardive
      Map<String, dynamic> userUpdateData = {
        'courses': userCourses.where((course) => course != courseId).toList(),
      };

      if (isPacchettoEntrate) {
        userUpdateData['entrateDisponibili'] = userSnapshot['entrateDisponibili'] + (shouldRefund ? 1 : 0);
      } else if (isAbbonamentoConLimiti && hoursDifference <= 2) {
        // Disdetta tardiva per abbonamenti con limiti settimanali
        if (!userConfirmed) {
          throw Exception('CONFIRMATION_REQUIRED_ABBONAMENTO');
        }
        
        // Incrementa il contatore delle disdette tardive per la settimana corrente
        Map<String, dynamic> currentDisdette = userSnapshot['disdetteTardiveSettimanali'] ?? {};
        String weekKey = WeekUtils.getWeekKey(startDate);
        currentDisdette[weekKey] = (currentDisdette[weekKey] ?? 0) + 1;
        
        userUpdateData['disdetteTardiveSettimanali'] = currentDisdette;
      }

      if (userCourses.contains(courseId)) {
        transaction.update(userRef, userUpdateData);
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
    print("Failed to unsubscribe: $error");
    throw error;
  });
}
