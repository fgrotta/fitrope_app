library;

/// Scarica un file di testo generato in memoria.
///
/// La condizione è **`dart.library.js_interop`, non `dart.library.html`**: sotto
/// `--wasm` (come si builda la produzione) `dart:html` non esiste e
/// `dart.library.html` è `false`, quindi la condizione classica sceglierebbe lo
/// stub proprio in produzione — e il bug sarebbe invisibile in
/// `flutter run -d chrome`, che compila in JS. Stesso pattern di
/// `clear_auth_persistence.dart`.
export 'download_file_stub.dart'
    if (dart.library.js_interop) 'download_file_web.dart';
