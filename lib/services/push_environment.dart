library;

/// Stato push del dispositivo e decisione su quale banner mostrare.
///
/// Deliberatamente **platform-free**: nessun `dart:js_interop`, nessun plugin.
/// `decidePushPrompt` è una funzione pura, ed è l'unico pezzo di questa feature
/// che `flutter test` può coprire davvero
/// (vedi `test/push_prompt_decision_test.dart`).

/// Permessi notifiche come li riporta la piattaforma.
/// `unsupported` = l'API non esiste proprio (iOS in tab Safari).
class PushEnvironment {
  /// `Notification` + `PushManager` + service worker disponibili.
  final bool hasApi;

  /// `default` | `granted` | `denied` | `unsupported`.
  final String permission;

  /// iPhone/iPad (incluso iPadOS, che manda uno UA da Mac).
  final bool ios;

  /// PWA installata (`navigator.standalone` **oppure** `display-mode`).
  final bool standalone;

  const PushEnvironment({
    required this.hasApi,
    required this.permission,
    required this.ios,
    required this.standalone,
  });

  /// Ambiente senza push: il default sicuro quando non sappiamo nulla.
  static const PushEnvironment unsupported = PushEnvironment(
    hasApi: false,
    permission: 'unsupported',
    ios: false,
    standalone: false,
  );

  @override
  String toString() =>
      'PushEnvironment(hasApi: $hasApi, permission: $permission, '
      'ios: $ios, standalone: $standalone)';
}

/// Cosa mostrare all'utente per le push su *questo* dispositivo.
enum PushPromptDecision {
  /// Nessun banner.
  hidden,

  /// Il permesso si può ancora chiedere: banner con bottone "Attiva".
  canRequest,

  /// iOS in tab Safari: la Web Push API non esiste finché la PWA non è
  /// installata. Istruzioni "Condividi → Aggiungi a Home", **senza** bottone.
  iosNeedsInstall,

  /// iOS con PWA installata ma senza API: iOS < 16.4, serve l'aggiornamento.
  iosNeedsUpdate,
}

/// Decide il banner push. Pura: nessun I/O, nessuna piattaforma.
///
/// - [preferenceEnabled]: `pushNotificationsEnabled` dell'utente su Firestore.
///   È un flag **cross-device**: se l'utente l'ha spento non gli si propone
///   nulla, e un diniego del browser non lo deve mai riscrivere a `false`.
/// - [simulating]: in simulazione non si parla mai con OneSignal.
/// - [snoozed]: l'utente ha già chiuso questo banner di recente.
///
/// Con permesso `denied` non si mostra nulla: in-app non c'è niente di
/// azionabile, il permesso si riattiva solo dalle impostazioni del browser.
PushPromptDecision decidePushPrompt({
  required PushEnvironment env,
  required bool preferenceEnabled,
  required bool simulating,
  required bool snoozed,
}) {
  if (simulating) return PushPromptDecision.hidden;
  if (!preferenceEnabled) return PushPromptDecision.hidden;
  if (snoozed) return PushPromptDecision.hidden;

  if (env.hasApi) {
    return env.permission == 'default'
        ? PushPromptDecision.canRequest
        : PushPromptDecision.hidden;
  }

  if (env.ios) {
    return env.standalone
        ? PushPromptDecision.iosNeedsUpdate
        : PushPromptDecision.iosNeedsInstall;
  }

  return PushPromptDecision.hidden;
}
