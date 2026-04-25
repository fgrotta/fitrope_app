import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('oneSignalInit')
external void _init(JSString appId);

@JS('oneSignalLogin')
external void _login(JSString userId);

@JS('oneSignalLogout')
external void _logout();

@JS('oneSignalAddEmail')
external void _addEmail(JSString email);

@JS('oneSignalRemoveEmail')
external void _removeEmail(JSString email);

@JS('oneSignalSetPushEnabled')
external void _setPushEnabled(JSBoolean enabled);

@JS('oneSignalSyncPushPreference')
external void _syncPushPreference(JSBoolean enabled);

@JS('oneSignalHasPushPermission')
external JSBoolean _hasPushPermission();

@JS('oneSignalCanRequestPushPermission')
external JSBoolean _canRequestPushPermission();

class OneSignalService {
  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal Web] initialize(appId: $appId)');
    _init(appId.toJS);
  }

  static void login(String userId) {
    debugPrint('🔔 [OneSignal Web] login(userId: $userId)');
    _login(userId.toJS);
  }

  static void addEmail(String email) {
    debugPrint('🔔 [OneSignal Web] addEmail(email: $email)');
    _addEmail(email.toJS);
  }

  static Future<void> removeEmail(String email) async {
    debugPrint('🔔 [OneSignal Web] removeEmail(email: $email)');
    _removeEmail(email.toJS);
  }

  static Future<void> setPushEnabled(bool enabled) async {
    debugPrint('🔔 [OneSignal Web] setPushEnabled(enabled: $enabled)');
    _setPushEnabled(enabled.toJS);
  }

  static Future<void> syncPushPreference(bool enabled) async {
    debugPrint('🔔 [OneSignal Web] syncPushPreference(enabled: $enabled)');
    _syncPushPreference(enabled.toJS);
  }

  static Future<bool> hasPushPermission() async {
    return _hasPushPermission().toDart;
  }

  static Future<bool> canRequestPushPermission() async {
    return _canRequestPushPermission().toDart;
  }

  static Future<void> logout() async {
    debugPrint('🔔 [OneSignal Web] logout()');
    _logout();
  }
}
