import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart' as os;

class OneSignalService {
  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal] initialize(appId: $appId)');
    os.OneSignal.initialize(appId);
    os.OneSignal.Notifications.requestPermission(true);
  }

  static void login(String userId) {
    debugPrint('🔔 [OneSignal] login(userId: $userId)');
    os.OneSignal.login(userId);
  }

  static void addEmail(String email) {
    debugPrint('🔔 [OneSignal] addEmail(email: $email)');
    os.OneSignal.User.addEmail(email);
  }

  static void logout() {
    debugPrint('🔔 [OneSignal] logout()');
    os.OneSignal.logout();
  }
}
