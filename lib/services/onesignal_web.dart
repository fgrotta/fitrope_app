import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:fitrope_app/services/push_environment.dart';
import 'package:fitrope_app/state/simulation_session.dart';

// Le funzioni del bridge (`web/index.html`) ritornano tutte una Promise che
// risolve SEMPRE, anche in errore: un reject attraverserebbe `JSPromise.toDart`
// come eccezione Dart e farebbe fallire i chiamanti (`saveChanges`, `signOut`).
// Prima erano fire-and-forget e ogni `await` qui sotto era finto.

@JS('oneSignalInit')
external JSPromise<JSAny?> _init(JSString appId);

@JS('oneSignalWhenReady')
external JSPromise<JSAny?> _whenReady();

@JS('oneSignalLogin')
external JSPromise<JSAny?> _login(JSString userId);

@JS('oneSignalLogout')
external JSPromise<JSAny?> _logout();

@JS('oneSignalAddEmail')
external JSPromise<JSAny?> _addEmail(JSString email);

@JS('oneSignalRemoveEmail')
external JSPromise<JSAny?> _removeEmail(JSString email);

@JS('oneSignalSetPushEnabled')
external JSPromise<JSBoolean> _setPushEnabled(JSBoolean enabled);

@JS('oneSignalSyncPushPreference')
external JSPromise<JSAny?> _syncPushPreference(JSBoolean enabled);

@JS('oneSignalRequestPushPermission')
external JSPromise<JSBoolean> _requestPushPermission();

@JS('oneSignalPushEnvironment')
external _JsPushEnvironment _pushEnvironment();

extension type _JsPushEnvironment._(JSObject _) implements JSObject {
  external JSBoolean get hasApi;
  external JSString get permission;
  external JSBoolean get ios;
  external JSBoolean get standalone;
}

class OneSignalService {
  // MODALITÀ SIMULAZIONE — difesa strutturale.
  // In simulazione `store.state.user` è l'utente simulato: senza queste guardie
  // il device dell'ADMIN verrebbe registrato su OneSignal come quell'utente, con
  // la sua email agganciata e le sue preferenze push applicate. Regola: in
  // simulazione non si chiama MAI OneSignal, il device resta legato all'admin.
  // Per questo `SimulationController.stop()` non deve ripristinare nulla.

  /// Resta `void`: gira al boot e non deve bloccarsi in attesa dello
  /// `<script defer>` del CDN. Chi ha bisogno dell'init completata usa
  /// [whenReady].
  static void initialize(String appId) {
    debugPrint('🔔 [OneSignal Web] initialize(appId: $appId)');
    _init(appId.toJS);
  }

  /// Risolve quando l'init OneSignal è completata (o subito, se non è mai
  /// partita). Non lancia mai.
  static Future<void> whenReady() async {
    await _whenReady().toDart;
  }

  static Future<void> login(String userId) async {
    SimulationSession.assertNotSimulating('OneSignal.login');
    debugPrint('🔔 [OneSignal Web] login(userId: $userId)');
    await _login(userId.toJS).toDart;
  }

  static Future<void> addEmail(String email) async {
    SimulationSession.assertNotSimulating('OneSignal.addEmail');
    debugPrint('🔔 [OneSignal Web] addEmail(email: $email)');
    await _addEmail(email.toJS).toDart;
  }

  static Future<void> removeEmail(String email) async {
    SimulationSession.assertNotSimulating('OneSignal.removeEmail');
    debugPrint('🔔 [OneSignal Web] removeEmail(email: $email)');
    await _removeEmail(email.toJS).toDart;
  }

  /// Applica la preferenza **senza** chiedere il permesso: l'opt-in richiede un
  /// gesto utente e passa da [requestPushPermission]. Ritorna lo stato
  /// effettivo del device.
  static Future<bool> setPushEnabled(bool enabled) async {
    SimulationSession.assertNotSimulating('OneSignal.setPushEnabled');
    debugPrint('🔔 [OneSignal Web] setPushEnabled(enabled: $enabled)');
    return (await _setPushEnabled(enabled.toJS).toDart).toDart;
  }

  static Future<void> syncPushPreference(bool enabled) async {
    SimulationSession.assertNotSimulating('OneSignal.syncPushPreference');
    debugPrint('🔔 [OneSignal Web] syncPushPreference(enabled: $enabled)');
    await _syncPushPreference(enabled.toJS).toDart;
  }

  /// Chiede il permesso notifiche e, se concesso, iscrive il device.
  ///
  /// Va chiamata come **prima istruzione** dell'`onPressed`: il bridge invoca
  /// `requestPermission()` in modo sincrono rispetto al tap, perché su WebKit
  /// la transient activation si perde al primo await e il prompt iOS non
  /// comparirebbe.
  static Future<bool> requestPushPermission() async {
    SimulationSession.assertNotSimulating('OneSignal.requestPushPermission');
    debugPrint('🔔 [OneSignal Web] requestPushPermission()');
    return (await _requestPushPermission().toDart).toDart;
  }

  /// Stato push del dispositivo. Nessuna guardia simulazione: non tocca
  /// l'identità, e il banner la interroga prima di decidere.
  static Future<PushEnvironment> pushEnvironment() async {
    final raw = _pushEnvironment();
    return PushEnvironment(
      hasApi: raw.hasApi.toDart,
      permission: raw.permission.toDart,
      ios: raw.ios.toDart,
      standalone: raw.standalone.toDart,
    );
  }

  static Future<void> logout() async {
    SimulationSession.assertNotSimulating('OneSignal.logout');
    debugPrint('🔔 [OneSignal Web] logout()');
    await _logout().toDart;
  }
}
