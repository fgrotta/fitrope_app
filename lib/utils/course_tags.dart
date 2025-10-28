/// Costanti per i tag dei corsi che limitano l'accesso degli utenti
class CourseTags {
  
  static const String PERSONAL_TRAINER = 'Personal Trainer';
  static const String OPEN = 'Open';
  static const String HEY_MAMMA = 'Hey Mamma';
  
  /// Lista di tutti i tag disponibili
  static List<String> get all => [ PERSONAL_TRAINER, OPEN, HEY_MAMMA];
  
  /// Tag di default per nuovi utenti
  static List<String> get defaultUserTags => [OPEN];
  
  /// Verifica se un utente può accedere a un corso basandosi sui tag
  /// 
  /// Logica:
  /// - Se l'utente ha il tag "Tutti i corsi" → può accedere a qualsiasi corso
  /// - Altrimenti, verificare se almeno uno dei tag utente corrisponde ai tag del corso
  /// - Se il corso non ha tag → accessibile a tutti
  static bool canUserAccessCourse(List<String> userTags, List<String> courseTags) {
    // Se l'utente ha "Tutti i corsi", può accedere a qualsiasi corso
    if (userTags.contains(OPEN)) {
      return true;
    }
    
    // Se il corso non ha tag, è accessibile a tutti
    if (courseTags.isEmpty) {
      return true;
    }
    
    // Verifica se almeno uno dei tag utente corrisponde ai tag del corso
    return userTags.any((userTag) => courseTags.contains(userTag));
  }
}
