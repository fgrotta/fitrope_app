import 'package:flutter/material.dart';

/// Manager per gestire il refresh dei certificati in scadenza
/// Permette di notificare tutte le pagine quando un certificato viene aggiornato
class CertificateRefreshManager {
  static final CertificateRefreshManager _instance = CertificateRefreshManager._internal();
  factory CertificateRefreshManager() => _instance;
  CertificateRefreshManager._internal();

  final List<VoidCallback> _listeners = [];

  /// Registra un listener per il refresh dei certificati
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Rimuove un listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifica tutti i listener che i certificati sono stati aggiornati
  void notifyRefresh() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        print('Errore nel notificare il refresh dei certificati: $e');
      }
    }
  }

  /// Pulisce tutti i listener (utile per evitare memory leak)
  void clearListeners() {
    _listeners.clear();
  }
}
