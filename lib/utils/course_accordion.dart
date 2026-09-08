/// Quale riga del calendario è aperta. Al massimo una.
///
/// L'accordion a riga singola è deliberato: limita il salto verticale e tiene
/// la giornata scansionabile, che è il motivo per cui la lista parte
/// dall'agenda compatta invece che dalle card.
///
/// Sta in una classe propria — e non in due righe dentro `CalendarPage` —
/// perché le regole di chiusura sono facili da dimenticare: in POC, cambiando
/// filtro, la riga aperta restava segnata e ricompariva da sola quando si
/// togliva il filtro.
class CourseAccordion {
  String? _expandedUid;

  /// `uid` del corso aperto, `null` se sono tutte chiuse.
  String? get expandedUid => _expandedUid;

  bool isExpanded(String uid) => _expandedUid == uid;

  /// Apre [uid], oppure lo chiude se era già aperto. Aprire una riga chiude
  /// automaticamente quella prima aperta.
  ///
  /// Ritorna `true` se lo stato è cambiato, così il chiamante può evitare un
  /// `setState` che non ridisegnerebbe nulla.
  bool toggle(String uid) {
    final next = _expandedUid == uid ? null : uid;
    if (next == _expandedUid) return false;
    _expandedUid = next;
    return true;
  }

  /// Chiude tutto. Va chiamata al cambio giorno e al cambio filtro: altrimenti
  /// l'uid resta puntato a un corso che non è più in lista e la riga si riapre
  /// da sola quando quel corso torna visibile.
  bool collapse() {
    if (_expandedUid == null) return false;
    _expandedUid = null;
    return true;
  }
}
