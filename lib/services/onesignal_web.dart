// Implementazione Web del servizio OneSignal — DISABILITATA.
//
// Le push web sono state disabilitate: il SDK OneSignal Web non viene più
// caricato in `web/index.html`. Su web le email vengono gestite server-side
// tramite la Cloud Function `ensureOneSignalUser` (crea l'utente OneSignal
// con email subscription al login) e le notifiche vengono inviate via
// `sendOneSignalNotification` usando `include_aliases.external_id`.
//
// Le push native restano attive solo su Android/iOS (vedi
// `onesignal_mobile.dart`).
//
// Tutti i metodi sono no-op. Se in futuro si vuole riattivare le push web,
// ripristinare il blocco commentato in `web/index.html` e reintrodurre le
// chiamate `@JS` a `window.oneSignalInit`, `oneSignalLogin`, ecc.

import 'package:flutter/foundation.dart';

class OneSignalService {
  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal Web] initialize: no-op (push web disabilitate)');
  }

  static void login(String userId) {
    debugPrint('🔔 [OneSignal Web] login: no-op (push web disabilitate)');
  }

  static void addEmail(String email) {
    // Le email passano via Cloud Function `ensureOneSignalUser`, non serve
    // registrarle sul Web SDK.
    debugPrint('🔔 [OneSignal Web] addEmail: no-op (gestito da Cloud Function)');
  }

  static Future<void> removeEmail(String email) async {
    debugPrint('🔔 [OneSignal Web] removeEmail: no-op (gestito da Cloud Function)');
  }

  static Future<void> logout() async {
    debugPrint('🔔 [OneSignal Web] logout: no-op (push web disabilitate)');
  }
}
