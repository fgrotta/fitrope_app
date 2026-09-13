import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart' as os;
import 'package:fitrope_app/state/simulation_session.dart';

class OneSignalService {
  // MODALITÀ SIMULAZIONE — difesa strutturale.
  // In simulazione `store.state.user` è l'utente simulato: senza queste guardie
  // il device dell'ADMIN verrebbe registrato su OneSignal come quell'utente, con
  // la sua email agganciata e le sue preferenze push applicate. Regola: in
  // simulazione non si chiama MAI OneSignal, il device resta legato all'admin.
  // Per questo `SimulationController.stop()` non deve ripristinare nulla.

  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal] initialize(appId: $appId)');
    os.OneSignal.initialize(appId);
  }

  static void login(String userId) {
    SimulationSession.assertNotSimulating('OneSignal.login');
    debugPrint('🔔 [OneSignal] login(userId: $userId)');
    os.OneSignal.login(userId);
  }

  static void addEmail(String email) {
    SimulationSession.assertNotSimulating('OneSignal.addEmail');
    debugPrint('🔔 [OneSignal] addEmail(email: $email)');
    os.OneSignal.User.addEmail(email);
  }

  static Future<void> removeEmail(String email) async {
    SimulationSession.assertNotSimulating('OneSignal.removeEmail');
    debugPrint('🔔 [OneSignal] removeEmail(email: $email)');
    await os.OneSignal.User.removeEmail(email);
  }

  static Future<void> setPushEnabled(bool enabled) async {
    SimulationSession.assertNotSimulating('OneSignal.setPushEnabled');
    debugPrint('🔔 [OneSignal] setPushEnabled(enabled: $enabled)');
    if (enabled) {
      final granted = await os.OneSignal.Notifications.requestPermission(true);
      if (granted) {
        await os.OneSignal.User.pushSubscription.optIn();
      }
      return;
    }

    await os.OneSignal.User.pushSubscription.optOut();
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

  static Future<bool> hasPushPermission() async {
    return os.OneSignal.Notifications.permission;
  }

  static Future<bool> canRequestPushPermission() async {
    return os.OneSignal.Notifications.canRequest();
  }

  static Future<void> logout() async {
    SimulationSession.assertNotSimulating('OneSignal.logout');
    debugPrint('🔔 [OneSignal] logout()');
    await os.OneSignal.logout();
  }
}
