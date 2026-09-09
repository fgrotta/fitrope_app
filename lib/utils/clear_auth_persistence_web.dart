import 'dart:async';
import 'dart:js_interop';

/// Nome del database IndexedDB in cui l'SDK Firebase JS tiene la sessione.
const String _kFirebaseAuthDb = 'firebaseLocalStorageDb';

@JS('indexedDB.deleteDatabase')
external _IdbOpenDbRequest _deleteDatabase(JSString name);

@JS('indexedDB')
external JSAny? get _indexedDb;

@JS('localStorage.removeItem')
external void _removeLocalStorageItem(JSString key);

@JS('localStorage')
external JSAny? get _localStorage;

@JS('sessionStorage.removeItem')
external void _removeSessionStorageItem(JSString key);

@JS('sessionStorage')
external JSAny? get _sessionStorage;

@JS()
extension type _IdbOpenDbRequest._(JSObject _) implements JSObject {
  external set onsuccess(JSFunction callback);
  external set onerror(JSFunction callback);
  external set onblocked(JSFunction callback);
}

/// Tetto all'attesa della cancellazione IndexedDB.
///
/// `deleteDatabase` richiede una versionchange, quindi si mette in coda dietro
/// ogni connessione aperta: con **due schede** dell'app aperte capita che non
/// arrivi né `success` né `error` né `blocked`, e senza un limite l'attesa non
/// finisce. Dato che questa funzione gira prima di `Firebase.initializeApp`,
/// un'attesa infinita significa app ferma sullo splash senza un messaggio.
const Duration _kDeleteTimeout = Duration(seconds: 3);

/// Chiave usata dalle persistence localStorage/sessionStorage di Firebase Auth.
String _authUserStorageKey(String apiKey, String appName) =>
    'firebase:authUser:$apiKey:$appName';

/// Cancella la sessione da tutti i backend configurati da `firebase_auth_web`:
/// IndexedDB, localStorage e sessionStorage.
///
/// La funzione è volutamente fail-closed: se non può garantire la rimozione,
/// propaga l'errore e impedisce all'app in modalità emulatore di proseguire con
/// una sessione che potrebbe appartenere alla produzione.
Future<void> clearFirebaseAuthPersistence({
  required String apiKey,
  required String appName,
}) async {
  final storageKey = _authUserStorageKey(apiKey, appName).toJS;

  try {
    if (_localStorage != null) _removeLocalStorageItem(storageKey);
    if (_sessionStorage != null) _removeSessionStorageItem(storageKey);
  } catch (error) {
    throw StateError(
      'Impossibile pulire la persistenza Firebase Auth nel Web Storage: '
      '$error',
    );
  }

  // Se IndexedDB non è disponibile, firebase_auth_web usa i fallback appena
  // puliti. Non c'è alcun database IndexedDB residuo da eliminare.
  if (_indexedDb == null) return;

  final completer = Completer<void>();
  late final _IdbOpenDbRequest request;
  try {
    request = _deleteDatabase(_kFirebaseAuthDb.toJS);
  } catch (error) {
    throw StateError(
      'Impossibile avviare la pulizia IndexedDB di Firebase Auth: $error',
    );
  }

  request.onsuccess = (() {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  request.onerror = (() {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('Cancellazione IndexedDB di Firebase Auth fallita'),
      );
    }
  }).toJS;
  request.onblocked = (() {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'Cancellazione IndexedDB di Firebase Auth bloccata: chiudi le altre '
          'schede dell\'app e riprova',
        ),
      );
    }
  }).toJS;

  try {
    await completer.future.timeout(_kDeleteTimeout);
  } on TimeoutException {
    // Fail-closed anche qui, ma con un motivo leggibile: proseguire
    // significherebbe rischiare di partire con una sessione di produzione.
    throw StateError(
      'Cancellazione IndexedDB di Firebase Auth senza risposta entro '
      '${_kDeleteTimeout.inSeconds}s: chiudi le altre schede dell\'app '
      '(la delete resta in coda dietro le connessioni aperte) e ricarica.',
    );
  }
}
