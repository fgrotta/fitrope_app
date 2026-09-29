import 'package:flutter/material.dart';
import 'package:fitrope_app/components/active_subscription_card.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/user_subscription.dart';

/// Elenco abbonamenti del dettaglio utente. Con [adminHistory] mostra lo
/// storico completo della collezione (anche scaduti e revocati) con i pulsanti
/// "Modifica" e "Revoca" sui non revocati; altrimenti è la vista di sola
/// lettura dello snapshot (Trainer, o storico non disponibile). I revocati
/// restano nascosti finché l'Admin non tocca "Mostra tutti".
///
/// Ordine: scadenza decrescente, tie-break su planKey (deterministico tra
/// rebuild). Le guardie di simulazione stanno nei callback della pagina.
class SubscriptionHistorySection extends StatefulWidget {
  final List<UserSubscription> subscriptions;
  final bool adminHistory;
  final bool busy;
  final ValueChanged<UserSubscription>? onEdit;
  final ValueChanged<UserSubscription>? onRevoke;

  const SubscriptionHistorySection({
    super.key,
    required this.subscriptions,
    required this.adminHistory,
    this.busy = false,
    this.onEdit,
    this.onRevoke,
  });

  static String titleFor({required bool adminHistory}) =>
      adminHistory ? 'Abbonamenti' : 'Abbonamenti attivi';

  @override
  State<SubscriptionHistorySection> createState() =>
      _SubscriptionHistorySectionState();
}

class _SubscriptionHistorySectionState
    extends State<SubscriptionHistorySection> {
  bool _showRevoked = false;

  bool _hasActions(UserSubscription s) =>
      widget.adminHistory && !s.isRevoked && s.id != null;

  @override
  Widget build(BuildContext context) {
    final adminHistory = widget.adminHistory;
    final busy = widget.busy;
    final all = [...widget.subscriptions]..sort((a, b) {
        final byEnd = b.endDate.compareTo(a.endDate);
        return byEnd != 0 ? byEnd : a.planKey.compareTo(b.planKey);
      });
    if (all.isEmpty) {
      return Text(
        adminHistory ? 'Nessun abbonamento' : 'Nessun abbonamento attivo',
        style: const TextStyle(color: onSurfaceVariantColor),
      );
    }
    final hasRevoked = all.any((s) => s.isRevoked);
    final subs = _showRevoked ? all : all.where((s) => !s.isRevoked).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Nessun abbonamento da mostrare',
              style: TextStyle(color: onSurfaceVariantColor),
            ),
          ),
        ...subs.map(
          (s) => ActiveSubscriptionCard(
            subscription: s,
            actions: !_hasActions(s)
                ? null
                : [
                    TextButton.icon(
                      onPressed: busy ? null : () => widget.onEdit?.call(s),
                      // Stesso colore di "Revoca": il primario di default
                      // non si legge sulla card scura.
                      style: TextButton.styleFrom(
                        foregroundColor: warningColor,
                        disabledForegroundColor:
                            warningColor.withValues(alpha: 0.38),
                      ),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Modifica'),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : () => widget.onRevoke?.call(s),
                      style: TextButton.styleFrom(
                        foregroundColor: warningColor,
                        disabledForegroundColor:
                            warningColor.withValues(alpha: 0.38),
                      ),
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Revoca'),
                    ),
                  ],
          ),
        ),
        if (hasRevoked)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showRevoked = !_showRevoked),
              child: Text(_showRevoked ? 'Nascondi revocati' : 'Mostra tutti'),
            ),
          ),
      ],
    );
  }
}

/// Conferma della revoca: true solo se l'Admin conferma.
Future<bool> confirmRevokeSubscription(BuildContext context) async =>
    (await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoca abbonamento'),
        content: const Text(
          'Procedere con la sostituzione dell\'abbonamento? Le prenotazioni già '
          'fatte restano valide e non verranno cancellate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const Key('revoke-subscription-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoca'),
          ),
        ],
      ),
    )) ??
    false;
