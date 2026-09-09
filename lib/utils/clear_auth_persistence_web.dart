import 'dart:js_interop';

/// Nome del database IndexedDB in cui l'SDK Firebase JS tiene la sessione.
const String _kFirebaseAuthDb = 'firebaseLocalStorageDb';

@JS('indexedDB.deleteDatabase')
external JSAny? _deleteDatabase(String name);

/// Cancella il database della sessione. Non si attende l'esito: IndexedDB
/// serializza le operazioni per nome di database, quindi una delete accodata
/// prima che l'SDK apra quel database viene eseguita per prima e l'SDK trova
/// una sessione vuota.
Future<void> clearFirebaseAuthPersistence() async {
  try {
    _deleteDatabase(_kFirebaseAuthDb);
  } catch (_) {
    // Se il browser la nega (storage partizionato, modalità restrittive) si
    // procede comunque: il peggio che accade è il comportamento di prima, che
    // il banner rosso mancante segnala.
  }
}
