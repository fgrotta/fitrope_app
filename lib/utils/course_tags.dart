/// Costanti per i tag dei corsi che limitano l'accesso degli utenti
class CourseTags {
  static const String PERSONAL_TRAINER = 'Personal Trainer';
  static const String OPEN = 'Open';
  static const String HYROX = 'Hyrox';
  static const String HEY_MAMMA = 'Hey Mamma';

  static const String YOGA = 'Yoga';
  static const String PILATES = 'Pilates';
  static const String CALISTHENICS = 'Calisthenics';
  static const String POSTURALE = 'Posturale';
  static const String TABATA = 'Tabata';
  static const String FITROPE = 'Fitrope';

  /// Tag descrittivi ammessi sui corsi V2. `Open` e `Hey Mamma` non sono tag:
  /// il primo e un tipo, il secondo e un valore storico in sola lettura.
  static const List<String> selectable = [
    PERSONAL_TRAINER,
    HYROX,
    YOGA,
    PILATES,
    CALISTHENICS,
    POSTURALE,
    TABATA,
    FITROPE,
  ];

  static const Set<String> legacyReadOnly = {HEY_MAMMA};

  /// Valori ancora mostrati nelle superfici anagrafiche legacy durante la
  /// bonifica utenti. Non include tag descrittivi ne Hey Mamma.
  static const List<String> legacyUserTypeTags = [OPEN, PERSONAL_TRAINER];

  /// Alias mantenuto per le superfici UI esistenti durante la migrazione.
  static List<String> get all => selectable;

  /// Tag di default per nuovi utenti
  static List<String> get defaultUserTags => [OPEN];

  static bool isSelectable(String? tag) =>
      tag != null && selectable.contains(tag);

  /// Mirror esatto per i client precedenti: il type tag e sempre il primo
  /// elemento; il tag descrittivo segue solo quando e diverso dal type tag.
  static List<String> legacyTagsMirror(String typeTag, String? tag) {
    if (tag == null || tag == typeTag) return [typeTag];
    return [typeTag, tag];
  }

  /// Tag descrittivo ricavato da un documento V1. `Open` indicava il tipo e
  /// quindi diventa null; Hey Mamma viene preservato per la sola lettura.
  static String? descriptiveTagFromLegacy(List<String> tags) {
    for (final tag in tags) {
      if (tag == OPEN) continue;
      if (selectable.contains(tag) || legacyReadOnly.contains(tag)) return tag;
    }
    return null;
  }

  /// Verifica se un utente può accedere a un corso basandosi sui tag
  ///
  /// Logica:
  /// - Se l'utente ha il tag "Tutti i corsi" → può accedere a qualsiasi corso
  /// - Altrimenti, verificare se almeno uno dei tag utente corrisponde ai tag del corso
  /// - Se il corso non ha tag → accessibile a tutti
  static bool canUserAccessCourse(
    List<String> userTags,
    List<String> courseTags,
  ) {
    // Se l'utente ha il tag "Tutti i corsi" → può accedere a qualsiasi corso
    if (userTags.contains('Tutti i corsi')) return true;

    // Caso 1: Utente senza TAG e corso senza TAG -> può iscriversi
    if (userTags.isEmpty && courseTags.isEmpty ||
        userTags.isEmpty && courseTags.contains(OPEN) ||
        userTags.contains(OPEN) && courseTags.isEmpty) {
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
