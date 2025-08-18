import 'package:flutter/material.dart';
import 'package:fitrope_app/api/courses/unsubscribeToCourse.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/course.dart';

/// Helper per gestire la disiscrizione ai corsi con controlli specifici per il Pacchetto Entrate
class CourseUnsubscribeHelper {
  
  /// Gestisce la disiscrizione da un corso con controlli automatici
  /// 
  /// [course] - Il corso da cui disiscriversi
  /// [user] - L'utente che si vuole disiscrivere
  /// [context] - Il contesto per mostrare dialog di conferma
  /// 
  /// Restituisce true se la disiscrizione è avvenuta con successo
  static Future<bool> handleUnsubscribe(
    Course course, 
    FitropeUser user, 
    BuildContext context
  ) async {
    print('🔍 CourseUnsubscribeHelper.handleUnsubscribe chiamato');
    print('📅 Corso: ${course.name} (${course.uid})');
    print('👤 Utente: ${user.name} ${user.lastName}');
    print('💳 Tipo abbonamento: ${user.tipologiaIscrizione}');
    
    // Prima verifica se serve conferma
    final unsubscribeInfo = canUnsubscribe(course, user);
    print('📊 Info disiscrizione: $unsubscribeInfo');
    
    if (unsubscribeInfo['requiresConfirmation']) {
      // Mostra dialog di conferma per perdita credito
      bool confirmed = await _showConfirmationDialog(context, course);   
      
      if (!confirmed) {
        print('❌ Disiscrizione annullata dall\'utente');
        return false; // L'utente ha annullato
      }
      
      // L'utente conferma di voler perdere il credito
      print('🔥 Esecuzione disiscrizione forzata (credito perso)');
      try {
        await forceUnsubscribeWithNoRefund(course.uid, user.uid);
        print('✅ Disiscrizione forzata completata');
        return true;
      } catch (e) {
        print('❌ Errore durante disiscrizione forzata: $e');
        _showErrorDialog(context, 'Errore durante la disiscrizione: $e');
        return false;
      }
    } else {
      print('✅ Disiscrizione normale con rimborso');
      // Disiscrizione normale con rimborso
      try {
        await unsubscribeToCourse(course.uid, user.uid);
        
        return true;
      } catch (e) {
        print('❌ Errore durante disiscrizione normale: $e');
        _showErrorDialog(context, 'Errore durante la disiscrizione: $e');
        return false;
      }
    }
  }
  
  /// Mostra il dialog di conferma per la perdita del credito
  static Future<bool> _showConfirmationDialog(BuildContext context, Course course) async {
    DateTime courseStart = course.startDate.toDate();
    String courseTime = '${courseStart.hour.toString().padLeft(2, '0')}:${courseStart.minute.toString().padLeft(2, '0')}';
    String courseDate = '${courseStart.day}/${courseStart.month}/${courseStart.year}';
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Disiscrizione'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stai per disiscriverti dal corso "${course.name}" del ${courseDate} alle ${courseTime}'),
              const SizedBox(height: 8),
              const Text(
                'ATTENZIONE: Mancano meno di 8 ore all\'inizio del corso, confermando la disiscrizione perderai definitivamente l\'ingresso.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sei sicuro di voler procedere?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Conferma Disiscrizione'),
            ),
          ],
        );
      },
    ) ?? false;
  }
  
  /// Mostra dialog di errore
  static void _showErrorDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Errore'),
          content: Text('Impossibile completare la disiscrizione: $errorMessage'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
  
  /// Verifica se un utente può disiscriversi da un corso
  /// 
  /// Restituisce informazioni su:
  /// - Se può disiscriversi
  /// - Se richiede conferma
  /// - Il messaggio da mostrare
  static Map<String, dynamic> canUnsubscribe(Course course, FitropeUser user) {
    print('🔍 canUnsubscribe chiamato per corso: ${course.name}');
    print('👤 Utente iscritto ai corsi: ${user.courses}');
    print('🎯 Corso da verificare: ${course.uid}');
    
    if (!user.courses.contains(course.uid)) {
      print('❌ Utente non iscritto al corso');
      return {
        'canUnsubscribe': false,
        'requiresConfirmation': false,
        'message': 'Non sei iscritto a questo corso',
        'isPacchettoEntrate': false,
      };
    }
    
    DateTime courseStart = course.startDate.toDate();
    DateTime now = DateTime.now();
    Duration difference = courseStart.difference(now);
    int hoursDifference = difference.inHours;
    
    print('📅 Inizio corso: $courseStart');
    print('🕐 Ora attuale: $now');
    print('⏰ Differenza ore: $hoursDifference');
    
    bool isPacchettoEntrate = user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE;
    bool requiresConfirmation = isPacchettoEntrate && hoursDifference <= 8;
    
    print('💳 È pacchetto entrate: $isPacchettoEntrate');
    print('⚠️ Richiede conferma: $requiresConfirmation');
    
    String message = '';
    if (requiresConfirmation) {
      message = 'Disiscrizione a meno di 8 ore: perderai il credito';
    } else if (isPacchettoEntrate) {
      message = 'Disiscrizione: il credito ti sarà rimborsato';
    } else {
      message = 'Disiscrizione: liberi il posto nel corso';
    }
    
    print('📝 Messaggio: $message');
    
    return {
      'canUnsubscribe': true,
      'requiresConfirmation': requiresConfirmation,
      'message': message,
      'isPacchettoEntrate': isPacchettoEntrate,
      'hoursRemaining': hoursDifference,
    };
  }
}
