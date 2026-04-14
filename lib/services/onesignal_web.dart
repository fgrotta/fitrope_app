import 'dart:js_interop';

@JS('oneSignalInit')
external void _init(JSString appId);

@JS('oneSignalLogin')
external void _login(JSString userId);

@JS('oneSignalLogout')
external void _logout();

@JS('oneSignalAddEmail')
external void _addEmail(JSString email);

class OneSignalService {
  static void initialize(String appId) {
    print('🔔 [OneSignal Web] initialize(appId: $appId)');
    _init(appId.toJS);
  }

  static void login(String userId) {
    print('🔔 [OneSignal Web] login(userId: $userId)');
    _login(userId.toJS);
  }

  static void addEmail(String email) {
    print('🔔 [OneSignal Web] addEmail(email: $email)');
    _addEmail(email.toJS);
  }

  static void logout() {
    print('🔔 [OneSignal Web] logout()');
    _logout();
  }
}
