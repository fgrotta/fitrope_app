library;

/// Snooze del banner "attiva le notifiche", persistito in `localStorage`.
///
/// La condizione è **`dart.library.js_interop`, non `dart.library.html`**: sotto
/// `--wasm` `dart:html` non esiste e `dart.library.html` è `false`, quindi la
/// condizione classica sceglierebbe lo stub proprio in produzione. Stesso
/// pattern di `download_file.dart`; il gate è `test/conditional_imports_test.dart`.
export 'push_prompt_prefs_stub.dart'
    if (dart.library.js_interop) 'push_prompt_prefs_web.dart';
