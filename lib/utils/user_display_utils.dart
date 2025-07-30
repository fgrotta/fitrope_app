import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/course.dart';

class UserDisplayUtils {
 

  /// Restituisce il nome da visualizzare per un utente (solo per admin o trainer)
  /// Se l'utente è anonimo, restituisce il nome completo con icona fantasma
  /// Altrimenti restituisce il nome completo
  static String getDisplayName(FitropeUser user, bool isAdmin) {

    if ( isAdmin) {
      if (user.isAnonymous) {
      return '${user.name} ${user.lastName} - (Anonimo)';
    }
    return '${user.name} ${user.lastName}';}
    else {
      if (user.isAnonymous) {
      return '(Anonimo)';
    }
    return '${user.name} ${user.lastName}';
    }
  }

  /// Verifica se un utente dovrebbe essere mostrato come anonimo
  /// Gli admin vedono sempre i nomi completi
  static bool shouldShowAsAnonymous(FitropeUser user, bool isAdmin) {
    return user.isAnonymous && !isAdmin;
  }

  /// Ottiene il nome del trainer da un ID
  static String getTrainerName(String? trainerId, List<FitropeUser> trainers) {
    if (trainerId == null || trainerId.isEmpty) {
      return 'Nessun trainer assegnato';
    }
    
    try {
      final trainer = trainers.where((user) => user.uid == trainerId).firstOrNull;
      
      if (trainer != null) {
        return '${trainer.name} ${trainer.lastName}';
      } else {
        return 'Trainer non trovato';
      }
    } catch (e) {
      print('Error getting trainer name: $e');
      return 'Errore nel caricamento trainer';
    }
  }
} 