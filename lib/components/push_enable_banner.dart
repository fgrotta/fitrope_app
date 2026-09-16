import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/services/push_environment.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

/// Barra che segnala che **questo dispositivo** non riceve le notifiche, anche
/// se l'utente le ha attive sul profilo.
///
/// Vive dentro `Protected` (nella `Column` sopra `AppShell`), non nel `builder`
/// di `MaterialApp` come [SimulationBanner]: lì coprirebbe anche il login e le
/// route pushate, dove non ha senso.
///
/// Con permesso `denied` non si mostra nulla (vedi [decidePushPrompt]): in-app
/// non c'è niente di azionabile, il permesso si riattiva solo dalle
/// impostazioni del browser.
class PushEnableBanner extends StatelessWidget {
  final PushPromptDecision decision;

  /// Chiude il banner per un po' (vedi [snoozeDurationFor]).
  final VoidCallback onDismiss;

  /// Chiede il permesso. Il chiamante **deve** invocare
  /// `OneSignalService.requestPushPermission()` come prima istruzione: qui è
  /// passata direttamente a `onPressed`, così la chiamata resta dentro la
  /// transient activation del tap (su WebKit altrimenti il prompt non compare).
  /// Assente quando non c'è nulla da chiedere (iOS in tab Safari: l'API non
  /// esiste proprio finché la PWA non è installata).
  final VoidCallback? onActivate;

  const PushEnableBanner({
    super.key,
    required this.decision,
    required this.onDismiss,
    this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    // Sotto i 600 px il messaggio si accorcia ma azione e chiusura restano
    // sempre raggiungibili: stesso criterio di SimulationBanner.
    final compatta = isMobile(context);
    final testo = _message(compatta);
    if (testo == null) return const SizedBox.shrink();

    // Niente SafeArea: `main.dart` avvolge già tutto in un SafeArea sopra
    // MaterialApp.
    return Material(
      color: primaryColor,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compatta ? 8 : 16),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_off_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  testo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onActivate != null)
                TextButton(
                  // Prima istruzione dell'onPressed, senza await interposti.
                  onPressed: onActivate,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  child: const Text('Attiva'),
                ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                tooltip: 'Nascondi',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _message(bool compatta) {
    switch (decision) {
      case PushPromptDecision.canRequest:
        return compatta
            ? 'Questo dispositivo non riceve le notifiche'
            : 'Le notifiche sono attive sul tuo profilo ma questo dispositivo '
                'non le riceve ancora';
      case PushPromptDecision.iosNeedsInstall:
        return compatta
            ? 'Aggiungi l\'app a Home per le notifiche'
            : 'Per ricevere le notifiche su iPhone: Condividi → Aggiungi a Home';
      case PushPromptDecision.iosNeedsUpdate:
        return compatta
            ? 'Aggiorna a iOS 16.4 per le notifiche'
            : 'Le notifiche richiedono iOS 16.4 o successivo: aggiorna il '
                'dispositivo';
      case PushPromptDecision.hidden:
        return null;
    }
  }
}
