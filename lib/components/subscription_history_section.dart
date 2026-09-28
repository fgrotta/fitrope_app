import 'package:flutter/material.dart';
import 'package:fitrope_app/components/active_subscription_card.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/user_subscription.dart';

/// Elenco abbonamenti del dettaglio utente. Con [adminHistory] mostra lo
/// storico completo della collezione (anche scaduti e revocati) con i pulsanti
/// "Modifica" e "Revoca" sui non revocati; altrimenti è la vista di sola
/// lettura dello snapshot (Trainer, o storico non disponibile).
///
/// Ordine: scadenza decrescente, tie-break su planKey (deterministico tra
/// rebuild). Le guardie di simulazione stanno nei callback della pagina.
class SubscriptionHistorySection extends StatelessWidget {
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

  bool _hasActions(UserSubscription s) =>
      adminHistory && !s.isRevoked && s.id != null;

  @override
  Widget build(BuildContext context) {
    final subs = [...subscriptions]..sort((a, b) {
        final byEnd = b.endDate.compareTo(a.endDate);
        return byEnd != 0 ? byEnd : a.planKey.compareTo(b.planKey);
      });
    if (subs.isEmpty) {
      return Text(
        adminHistory ? 'Nessun abbonamento' : 'Nessun abbonamento attivo',
        style: const TextStyle(color: onSurfaceVariantColor),
      );
    }
    return Column(
      children: subs
          .map(
            (s) => ActiveSubscriptionCard(
              subscription: s,
              actions: !_hasActions(s)
                  ? null
                  : [
                      TextButton.icon(
                        onPressed: busy ? null : () => onEdit?.call(s),
                        // Card scura: il primario di default non si legge.
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white38,
                        ),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Modifica'),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : () => onRevoke?.call(s),
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
          )
          .toList(),
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
