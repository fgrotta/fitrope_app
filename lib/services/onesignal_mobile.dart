import 'package:onesignal_flutter/onesignal_flutter.dart' as os;

class OneSignalService {
  static void initialize(String appId) {
    os.OneSignal.initialize(appId);
    os.OneSignal.Notifications.requestPermission(true);
  }

  static void login(String userId) {
    os.OneSignal.login(userId);
  }

  static void addEmail(String email) {
    os.OneSignal.User.addEmail(email);
  }

  static void logout() {
    os.OneSignal.logout();
  }
}
