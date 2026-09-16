import 'package:fitrope_app/services/push_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ambiente "browser desktop normale" con il permesso indicato.
PushEnvironment _desktop(String permission) => PushEnvironment(
      hasApi: true,
      permission: permission,
      ios: false,
      standalone: false,
    );

/// iOS senza Web Push API: in tab Safari (`standalone: false`) o con la PWA
/// installata su iOS < 16.4 (`standalone: true`).
PushEnvironment _ios({required bool standalone}) => PushEnvironment(
      hasApi: false,
      permission: 'unsupported',
      ios: true,
      standalone: standalone,
    );

PushPromptDecision _decide(
  PushEnvironment env, {
  bool preferenceEnabled = true,
  bool simulating = false,
  bool snoozed = false,
}) =>
    decidePushPrompt(
      env: env,
      preferenceEnabled: preferenceEnabled,
      simulating: simulating,
      snoozed: snoozed,
    );

void main() {
  group('decidePushPrompt', () {
    test('permesso ancora richiedibile → si propone l\'attivazione', () {
      expect(_decide(_desktop('default')), PushPromptDecision.canRequest);
    });

    test('permesso già concesso → nessun banner', () {
      expect(_decide(_desktop('granted')), PushPromptDecision.hidden);
    });

    test('permesso negato → nessun banner (in-app non c\'è nulla da fare)', () {
      expect(_decide(_desktop('denied')), PushPromptDecision.hidden);
    });

    test('iOS in tab Safari → istruzioni per installare la PWA', () {
      expect(
        _decide(_ios(standalone: false)),
        PushPromptDecision.iosNeedsInstall,
      );
    });

    test('iOS con PWA installata ma senza API → serve iOS 16.4+', () {
      expect(
        _decide(_ios(standalone: true)),
        PushPromptDecision.iosNeedsUpdate,
      );
    });

    test('browser senza API e non iOS → nessun banner', () {
      expect(_decide(PushEnvironment.unsupported), PushPromptDecision.hidden);
    });

    test('preferenza utente spenta → nessun banner, in ogni ambiente', () {
      // pushNotificationsEnabled è un opt-out esplicito dell'utente: non gli si
      // ripropone l'attivazione su questo dispositivo.
      for (final env in [
        _desktop('default'),
        _ios(standalone: false),
        _ios(standalone: true),
      ]) {
        expect(
            _decide(env, preferenceEnabled: false), PushPromptDecision.hidden);
      }
    });

    test('in simulazione non si mostra mai nulla', () {
      // Il bottone "Attiva" chiamerebbe requestPushPermission(), che è guardato
      // e lancerebbe: il banner non deve proprio comparire.
      for (final env in [
        _desktop('default'),
        _ios(standalone: false),
        _ios(standalone: true),
      ]) {
        expect(_decide(env, simulating: true), PushPromptDecision.hidden);
      }
    });

    test('snooze attivo → nessun banner', () {
      for (final env in [
        _desktop('default'),
        _ios(standalone: false),
        _ios(standalone: true),
      ]) {
        expect(_decide(env, snoozed: true), PushPromptDecision.hidden);
      }
    });
  });

  group('snoozeDurationFor', () {
    test('14 giorni per la richiesta di permesso, 30 per i percorsi iOS', () {
      expect(
        snoozeDurationFor(PushPromptDecision.canRequest),
        const Duration(days: 14),
      );
      expect(
        snoozeDurationFor(PushPromptDecision.iosNeedsInstall),
        const Duration(days: 30),
      );
      expect(
        snoozeDurationFor(PushPromptDecision.iosNeedsUpdate),
        const Duration(days: 30),
      );
    });

    test('hidden non ha nulla da rimandare', () {
      expect(snoozeDurationFor(PushPromptDecision.hidden), Duration.zero);
    });
  });
}
