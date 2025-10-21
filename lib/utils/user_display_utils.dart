import 'package:fitrope_app/types/fitropeUser.dart';

class UserDisplayUtils {
 

  /// Restituisce il nome da visualizzare per un utente (solo per admin o trainer)
  /// Se l'utente è anonimo, restituisce il nome completo con icona fantasma
  /// Se l'utente ha un abbonamento di prova, mostra "(Prova)"
  /// Altrimenti restituisce il nome completo
  static String getDisplayName(FitropeUser user, bool isAdmin) {
    String baseName = '${user.name} ${user.lastName}';
    
    if (isAdmin) {
      if (user.isAnonymous) {
        return '$baseName - (Anonimo)';
      }
      if (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA) {
        return '$baseName - (Prova)';
      }
      return baseName;
    } else {
      if (user.isAnonymous) {
        return '(Anonimo)';
      }
      return baseName;
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