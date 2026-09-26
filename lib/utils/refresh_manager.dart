import 'package:flutter/material.dart';

/// Manager per gestire il refresh dei certificati in scadenza
/// Permette di notificare tutte le pagine quando un certificato viene aggiornato
class RefreshManager {
  static final RefreshManager _instance = RefreshManager._internal();
  factory RefreshManager() => _instance;
  RefreshManager._internal();

  final List<VoidCallback> _listeners = [];

  /// Registra un listener per il refresh dei certificati
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Rimuove un listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifica tutti i listener che sono stati aggiornati
  ///
  /// Si itera su una copia: un listener può aggiungere o togliere listener
  /// mentre riceve la notifica (uno State che si smonta, una pagina che ne
  /// monta un'altra), e iterare sulla lista viva lancerebbe una
  /// ConcurrentModificationError FUORI dal try, saltando tutti i listener
  /// successivi. Chi viene rimosso durante il giro non viene più chiamato
  /// (il suo State è in dispose); chi viene aggiunto parte dal giro dopo.
  void notifyRefresh() {
    for (final listener in List.of(_listeners)) {
      if (!_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (e) {
        debugPrint('Errore nel notificare il refresh dei certificati: $e');
      }
    }
  }

  /// Numero di listener registrati: serve ai test per verificare che ogni
  /// State tolga in dispose esattamente ciò che ha aggiunto in initState.
  @visibleForTesting
  int get listenerCount => _listeners.length;

  /// Pulisce tutti i listener (utile per evitare memory leak)
  void clearListeners() {
    _listeners.clear();
  }
}

/// Unico modo in cui uno State si aggancia a [RefreshManager]: [listenToRefresh]
/// registra e ricorda il callback, e `dispose` toglie tutti e soli i callback
/// registrati da questo State.
///
/// Serve a non ricalcolare in dispose cosa togliere. HomePage lo faceva da
/// `user.role`, che `refreshCourses` può cambiare copiando lo store (in
/// simulazione lo store passa dal socio all'admin mentre la Home del socio è
/// ancora montata): i listener del ruolo iniziale restavano agganciati a uno
/// State morto per tutta la sessione.
mixin RefreshListenersMixin<T extends StatefulWidget> on State<T> {
  final List<VoidCallback> _refreshListeners = [];

  @protected
  void listenToRefresh(VoidCallback listener) {
    _refreshListeners.add(listener);
    RefreshManager().addListener(listener);
  }

  @override
  void dispose() {
    for (final listener in _refreshListeners) {
      RefreshManager().removeListener(listener);
    }
    _refreshListeners.clear();
    super.dispose();
  }
}
