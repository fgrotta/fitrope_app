import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

FirebaseFirestore firestore = FirebaseFirestore.instance;

// Funzione per la disiscrizione normale (sempre rimborsa il credito se applicabile)
Future<void> unsubscribeToCourse(String courseId, String userId) async {
  try {
    print('=== INIZIO unsubscribeToCourse ===');
    print('courseId: $courseId');
    print('userId: $userId');
    
    QuerySnapshot querySnapshot = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      print('❌ Corso non trovato: $courseId');
      throw Exception('Course does not exist');
    }

    DocumentReference courseRef = querySnapshot.docs.first.reference;

    await firestore.runTransaction((transaction) async {
      store.dispatch(StartLoadingAction());
      
      try {
        // PRIMA: Esegui TUTTE le letture
        DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
        
        DocumentReference userRef = firestore.collection('users').doc(userId);
        
        DocumentSnapshot userSnapshot = await transaction.get(userRef);
        
        // Verifica i dati letti
        int subscribed = courseSnapshot['subscribed'];

        if (subscribed > 0) {
          List<dynamic> userCourses = userSnapshot['courses'] ?? [];

          if (userCourses.contains(courseId)) {
            // DOPO: Esegui TUTTE le scritture
            
            // Aggiorna il contatore del corso
            transaction.update(courseRef, {
              'subscribed': subscribed - 1,
            });

            // Rimuovi il corso dalla lista utente
            userCourses.remove(courseId);

            // Prepara i dati per l'aggiornamento utente
            String? tipologiaIscrizione = userSnapshot['tipologiaIscrizione'];
            bool isPacchettoEntrate = tipologiaIscrizione == 'PACCHETTO_ENTRATE';
            int? entrateDisponibili = userSnapshot['entrateDisponibili'];
            
            if (isPacchettoEntrate) {
              int nuoveEntrate = (entrateDisponibili ?? 0) + 1;
              print('💳 Nuove entrate disponibili: $nuoveEntrate');
            }
            
            // Aggiorna l'utente
            transaction.update(userRef, {
              'courses': userCourses,
              'entrateDisponibili': userSnapshot['entrateDisponibili'] + (isPacchettoEntrate ? 1 : 0)
            });
            
              
          } else {
            print('❌ Utente non iscritto al corso');
            throw Exception('User is not subscribed to this course');
          }
        } else {
          print('❌ Nessun utente iscritto al corso');
          throw Exception('No users subscribed to this course');
        }
        
      } catch (e, stackTrace) {
        print('❌ Errore durante la transazione:');
        print('Errore: $e');
        print('Stack trace: $stackTrace');
        rethrow;
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
    }).catchError((error, stackTrace) {
      print('❌ Errore nella gestione post-transazione:');
      print('Errore: $error');
      print('Stack trace: $stackTrace');
      store.dispatch(FinishLoadingAction());
      print("Failed to unsubscribe: $error");
      throw error;
    });
    
  } catch (e, stackTrace) {
    print('❌ Errore generale in unsubscribeToCourse:');
    print('Errore: $e');
    print('Stack trace: $stackTrace');
    print('Tipo di errore: ${e.runtimeType}');
    
    // Se è un'eccezione Firestore, mostra più dettagli
    if (e is FirebaseException) {
      print('🔥 Firebase Exception Details:');
      print('  Code: ${e.code}');
      print('  Message: ${e.message}');
    }
    
    rethrow;
  }
}

// Funzione per la disiscrizione forzata quando l'utente conferma di perdere il credito
Future<void> forceUnsubscribeWithNoRefund(String courseId, String userId) async {
  try {
    
    QuerySnapshot querySnapshot = await firestore
        .collection('courses')
        .where('uid', isEqualTo: courseId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      print('❌ Corso non trovato: $courseId');
      throw Exception('Course does not exist');
    }

    DocumentReference courseRef = querySnapshot.docs.first.reference;
    
    await firestore.runTransaction((transaction) async {
      store.dispatch(StartLoadingAction());
      
      try {
        // PRIMA: Esegui TUTTE le letture
        DocumentSnapshot courseSnapshot = await transaction.get(courseRef);
        
        DocumentReference userRef = firestore.collection('users').doc(userId);
        
        DocumentSnapshot userSnapshot = await transaction.get(userRef);
        
        // Verifica i dati letti
        int subscribed = courseSnapshot['subscribed'];

        if (subscribed > 0) {
          List<dynamic> userCourses = userSnapshot['courses'] ?? [];

          if (userCourses.contains(courseId)) {
            
            // Aggiorna il contatore del corso
            transaction.update(courseRef, {
              'subscribed': subscribed - 1,
            });
            // Rimuovi il corso dalla lista utente
            userCourses.remove(courseId);

            // Per la disiscrizione forzata, non viene mai rimborsato il credito
            // indipendentemente dal tipo di abbonamento
            transaction.update(userRef, {
              'courses': userCourses,
              // Non incrementa entrateDisponibili - il credito viene perso
            });
            
            
          } else {
            print('❌ Utente non iscritto al corso');
            throw Exception('User is not subscribed to this course');
          }
        } else {
          print('❌ Nessun utente iscritto al corso');
          throw Exception('No users subscribed to this course');
        }
        
      } catch (e, stackTrace) {
        print('❌ Errore durante la transazione (no refund):');
        print('Errore: $e');
        print('Stack trace: $stackTrace');
        rethrow;
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
    }).catchError((error, stackTrace) {
      print('❌ Errore nella gestione post-transazione (no refund):');
      print('Errore: $error');
      print('Stack trace: $stackTrace');
      store.dispatch(FinishLoadingAction());
      print("Failed to force unsubscribe with no refund: $error");
      throw error;
    });
    
  } catch (e, stackTrace) {
    print('❌ Errore generale in forceUnsubscribeWithNoRefund:');
    print('Errore: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}
