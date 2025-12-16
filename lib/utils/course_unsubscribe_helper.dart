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
      // Mostra dialog di conferma per perdita credito/ingresso settimanale
      bool confirmed = await _showConfirmationDialog(
        context, 
        course,
        isTemporalSubscription: unsubscribeInfo['isTemporalSubscription'] ?? false,
      );   
      
      if (!confirmed) {
        print('❌ Disiscrizione annullata dall\'utente');
        return false; // L'utente ha annullato
      }
      
      // L'utente conferma di voler perdere il credito/ingresso settimanale
      print('🔥 Esecuzione disiscrizione forzata (credito/ingresso perso)');
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
  
  /// Mostra il dialog di conferma per la perdita del credito o ingresso settimanale
  static Future<bool> _showConfirmationDialog(
    BuildContext context, 
    Course course,
    {required bool isTemporalSubscription}
  ) async {
    DateTime courseStart = course.startDate.toDate();
    String courseTime = '${courseStart.hour.toString().padLeft(2, '0')}:${courseStart.minute.toString().padLeft(2, '0')}';
    String courseDate = '${courseStart.day}/${courseStart.month}/${courseStart.year}';
    
    // Determina il messaggio in base al tipo di abbonamento
    String warningMessage;
    int hoursThreshold = isTemporalSubscription ? 4 : 8;
    
    if (isTemporalSubscription) {
      warningMessage = 'ATTENZIONE: Mancano meno di $hoursThreshold ore all\'inizio del corso, confermando la disiscrizione perderai definitivamente l\'ingresso settimanale per questa settimana.';
    } else {
      warningMessage = 'ATTENZIONE: Mancano meno di $hoursThreshold ore all\'inizio del corso, confermando la disiscrizione perderai definitivamente l\'ingresso.';
    }
    
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
              Text(
                warningMessage,
                style: const TextStyle(
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
    bool isAbbonamentoProva = user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA;
    bool isTemporalSubscription = user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
        user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
        user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
        user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE;
    
    // Per pacchetti entrate: conferma se <= 8 ore
    // Per abbonamenti temporali: conferma se <= 4 ore
    bool requiresConfirmation = false;
    if (isPacchettoEntrate || isAbbonamentoProva) {
      requiresConfirmation = hoursDifference <= 8;
    } else if (isTemporalSubscription) {
      requiresConfirmation = hoursDifference <= 4;
    }
    
    print('💳 È pacchetto entrate: $isPacchettoEntrate');
    print('📅 È abbonamento temporale: $isTemporalSubscription');
    print('⚠️ Richiede conferma: $requiresConfirmation');
    
    String message = '';
    if (requiresConfirmation) {
      if (isTemporalSubscription) {
        message = 'Disiscrizione a meno di 4 ore: perderai l\'ingresso settimanale';
      } else {
        message = 'Disiscrizione a meno di 8 ore: perderai il credito';
      }
    } else if (isPacchettoEntrate || isAbbonamentoProva) {
      message = 'Disiscrizione: il credito ti sarà rimborsato';
    } else {
      message = 'Disiscrizione: liberi il posto nel corso';
    }
    
    print('📝 Messaggio: $message');
    
    return {
      'canUnsubscribe': true,
      'requiresConfirmation': requiresConfirmation,
      'message': message,
      'isPacchettoEntrate': isPacchettoEntrate || isAbbonamentoProva,
      'isTemporalSubscription': isTemporalSubscription,
      'hoursRemaining': hoursDifference,
    };
  }
}
