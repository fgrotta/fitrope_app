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
    _init(appId.toJS);
  }

  static void login(String userId) {
    _login(userId.toJS);
  }

  static void addEmail(String email) {
    _addEmail(email.toJS);
  }

  static void logout() {
    _logout();
  }
}
