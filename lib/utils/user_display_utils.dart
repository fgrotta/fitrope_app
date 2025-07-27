import 'package:fitrope_app/types/fitropeUser.dart';

class UserDisplayUtils {
 

  /// Restituisce il nome da visualizzare per un utente (solo per admin)
  /// Se l'utente è anonimo, restituisce il nome completo con icona fantasma
  /// Altrimenti restituisce il nome completo
  static String getDisplayName(FitropeUser user, bool isAdmin) {

    if ( isAdmin) {
      if (user.isAnonymous) {
      return '${user.name} ${user.lastName} - ${user.email} (Anonimo)';
    }
    return '${user.name} ${user.lastName} - ${user.email}';}
    else {
      if (user.isAnonymous) {
      return '(Anonimo)';
    }
    return '${user.name} ${user.lastName} - ${user.email}';
    }
  }

  /// Verifica se un utente dovrebbe essere mostrato come anonimo
  /// Gli admin vedono sempre i nomi completi
  static bool shouldShowAsAnonymous(FitropeUser user, bool isAdmin) {
    return user.isAnonymous && !isAdmin;
  }
} 