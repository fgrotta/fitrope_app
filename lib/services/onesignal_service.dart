library;

/// Facciata unica su OneSignal: implementazione mobile (plugin
/// `onesignal_flutter`) oppure web (bridge JS in `web/index.html`).
///
/// La condizione è **`dart.library.js_interop`, non `dart.library.html`**: sotto
/// `--wasm` (usato in produzione fino al 26/09/2026, e riattivabile) `dart:html`
/// non esiste e `dart.library.html` è `false`, quindi la condizione classica
/// sceglie il ramo *mobile* proprio sul web. Il sintomo è una raffica di
/// `MissingPluginException(No implementation found for method OneSignal#initialize
/// on channel OneSignal)` in console, con il bridge JS mai invocato: niente
/// service worker registrato, niente push, niente alias email.
///
/// Il bug è invisibile in `flutter run -d chrome`, che compila in dart2js dove
/// `dart.library.html` è `true`. Stesso pattern di `lib/utils/download_file.dart`
/// e `lib/utils/clear_auth_persistence.dart`; il gate anti-regressione è
/// `test/conditional_imports_test.dart`.
export 'onesignal_mobile.dart'
    if (dart.library.js_interop) 'onesignal_web.dart';
