import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart' as os;
import 'package:fitrope_app/services/push_environment.dart';
import 'package:fitrope_app/state/simulation_session.dart';

class OneSignalService {
  // MODALITÀ SIMULAZIONE — difesa strutturale.
  // In simulazione `store.state.user` è l'utente simulato: senza queste guardie
  // il device dell'ADMIN verrebbe registrato su OneSignal come quell'utente, con
  // la sua email agganciata e le sue preferenze push applicate. Regola: in
  // simulazione non si chiama MAI OneSignal, il device resta legato all'admin.
  // Per questo `SimulationController.stop()` non deve ripristinare nulla.
  //
  // Le firme sono tenute simmetriche a `onesignal_web.dart`: il conditional
  // export le sostituisce l'una all'altra, quindi ogni divergenza rompe la
  // compilazione di una sola piattaforma (e la si scopre tardi).

  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal] initialize(appId: $appId)');
    os.OneSignal.initialize(appId);
  }

  /// Sul plugin nativo l'inizializzazione è sincrona: nulla da attendere.
  static Future<void> whenReady() async {}

  static Future<void> login(String userId) async {
    SimulationSession.assertNotSimulating('OneSignal.login');
    debugPrint('🔔 [OneSignal] login(userId: $userId)');
    os.OneSignal.login(userId);
  }

  static Future<void> addEmail(String email) async {
    SimulationSession.assertNotSimulating('OneSignal.addEmail');
    debugPrint('🔔 [OneSignal] addEmail(email: $email)');
    os.OneSignal.User.addEmail(email);
  }

  static Future<void> removeEmail(String email) async {
    SimulationSession.assertNotSimulating('OneSignal.removeEmail');
    debugPrint('🔔 [OneSignal] removeEmail(email: $email)');
    await os.OneSignal.User.removeEmail(email);
  }

  /// Applica la preferenza **senza** chiedere il permesso (quello passa da
  /// [requestPushPermission]). Ritorna lo stato effettivo del device.
  static Future<bool> setPushEnabled(bool enabled) async {
    SimulationSession.assertNotSimulating('OneSignal.setPushEnabled');
    debugPrint('🔔 [OneSignal] setPushEnabled(enabled: $enabled)');
    if (!enabled) {
      await os.OneSignal.User.pushSubscription.optOut();
      return false;
    }

    if (!os.OneSignal.Notifications.permission) return false;
    await os.OneSignal.User.pushSubscription.optIn();
    return true;
  }

  static Future<void> syncPushPreference(bool enabled) async {
    SimulationSession.assertNotSimulating('OneSignal.syncPushPreference');
    debugPrint('🔔 [OneSignal] syncPushPreference(enabled: $enabled)');
    if (!enabled) {
      await os.OneSignal.User.pushSubscription.optOut();
      return;
    }

    if (os.OneSignal.Notifications.permission &&
        os.OneSignal.User.pushSubscription.optedIn == false) {
      await os.OneSignal.User.pushSubscription.optIn();
    }
  }

  static Future<bool> requestPushPermission() async {
    SimulationSession.assertNotSimulating('OneSignal.requestPushPermission');
    debugPrint('🔔 [OneSignal] requestPushPermission()');
    final granted = await os.OneSignal.Notifications.requestPermission(true);
    if (!granted) return false;
    await os.OneSignal.User.pushSubscription.optIn();
    return true;
  }

  /// Sull'app nativa non esiste il percorso "aggiungi a Home": `standalone` è
  /// sempre vero e `ios` resta falso, così `decidePushPrompt` non propone mai
  /// l'installazione. `denied` si deduce da `canRequest()`.
  static Future<PushEnvironment> pushEnvironment() async {
    if (os.OneSignal.Notifications.permission) {
      return const PushEnvironment(
        hasApi: true,
        permission: 'granted',
        ios: false,
        standalone: true,
      );
    }
    final canRequest = await os.OneSignal.Notifications.canRequest();
    return PushEnvironment(
      hasApi: true,
      permission: canRequest ? 'default' : 'denied',
      ios: false,
      standalone: true,
    );
  }

  static Future<void> logout() async {
    SimulationSession.assertNotSimulating('OneSignal.logout');
    debugPrint('🔔 [OneSignal] logout()');
    await os.OneSignal.logout();
  }
}
