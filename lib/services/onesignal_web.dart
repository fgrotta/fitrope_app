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
  static bool _enabled = true;
  static bool get isEnabled => _enabled;
  static void setEnabled(bool enabled) => _enabled = enabled;

  static void initialize(String appId) {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] initialize(appId: $appId)');
    _init(appId.toJS);
  }

  static void login(String userId) {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] login(userId: $userId)');
    _login(userId.toJS);
  }

  static void addEmail(String email) {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] addEmail(email: $email)');
    _addEmail(email.toJS);
  }

  static Future<void> removeEmail(String email) async {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] removeEmail(email: $email)');
    _removeEmail(email.toJS);
  }

  static Future<void> setPushEnabled(bool enabled) async {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] setPushEnabled(enabled: $enabled)');
    _setPushEnabled(enabled.toJS);
  }

  static Future<void> syncPushPreference(bool enabled) async {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] syncPushPreference(enabled: $enabled)');
    _syncPushPreference(enabled.toJS);
  }

  static Future<bool> hasPushPermission() async {
    if (!_enabled) return false;
    return _hasPushPermission().toDart;
  }

  static Future<bool> canRequestPushPermission() async {
    if (!_enabled) return false;
    return _canRequestPushPermission().toDart;
  }

  static Future<void> logout() async {
    if (!_enabled) return;
    debugPrint('🔔 [OneSignal Web] logout()');
    _logout();
  }
}
