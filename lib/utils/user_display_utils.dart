import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/week_utils.dart';

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

String getDisdetteTardiveInfo(FitropeUser user) {
  if (user.disdetteTardiveSettimanali == null || user.disdetteTardiveSettimanali!.isEmpty) {
    return 'Nessuna disdetta tardiva';
  }

  List<String> info = [];
  user.disdetteTardiveSettimanali!.forEach((weekKey, count) {
    // Parsing della chiave settimana (YYYY-WW)
    List<String> parts = weekKey.split('-');
    if (parts.length == 2) {
      int year = int.tryParse(parts[0]) ?? 0;
      int week = int.tryParse(parts[1]) ?? 0;
      info.add('Settimana $week/$year: $count disdette tardive');
    }
  });

  return info.join(', ');
}

String getCurrentWeekDisdetteTardive(FitropeUser user) {
  if (user.disdetteTardiveSettimanali == null) return '0';
  
  String currentWeekKey = WeekUtils.getWeekKey(DateTime.now());
  int count = user.disdetteTardiveSettimanali![currentWeekKey] ?? 0;
  return count.toString();
} 