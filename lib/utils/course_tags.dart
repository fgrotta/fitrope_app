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
    // Caso 1: Utente senza TAG e corso senza TAG -> può iscriversi
    if (userTags.isEmpty && courseTags.isEmpty || userTags.isEmpty && courseTags.contains(OPEN) || userTags.contains(OPEN) && courseTags.isEmpty) {
      return true;
    }
    
    // Caso 2: Se l'utente ha almeno un TAG del corso -> può iscriversi
    if (userTags.any((userTag) => courseTags.contains(userTag))) {
      return true;
    }
    
    // Caso 3: Utente senza TAG ma corso ha TAG (diverso da OPEN) -> NON può iscriversi
    // Questo caso è già gestito implicitamente: se userTags.isEmpty e courseTags non è vuoto
    // e non c'è corrispondenza, la funzione tornerà false alla fine
    
    // Tutti gli altri casi -> NON può iscriversi
    return false;
  }
}
