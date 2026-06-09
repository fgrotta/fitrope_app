import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart' as os;

class OneSignalService {
  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal] initialize(appId: $appId)');
    os.OneSignal.initialize(appId);
  }

  static void login(String userId) {
    debugPrint('🔔 [OneSignal] login(userId: $userId)');
    os.OneSignal.login(userId);
  }

  static void addEmail(String email) {
    debugPrint('🔔 [OneSignal] addEmail(email: $email)');
    os.OneSignal.User.addEmail(email);
  }

  static Future<void> removeEmail(String email) async {
    debugPrint('🔔 [OneSignal] removeEmail(email: $email)');
    await os.OneSignal.User.removeEmail(email);
  }

  static Future<void> setPushEnabled(bool enabled) async {
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
    debugPrint('🔔 [OneSignal] logout()');
    await os.OneSignal.logout();
  }
}
