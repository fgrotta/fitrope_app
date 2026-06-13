import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';

/// Card di sola lettura per un singolo abbonamento del modello multi-abbonamento.
/// Mostra titolo del piano, residui/frequenza e scadenza colorata in base allo
/// stato (verde valido / arancio in scadenza / rosso scaduto).
///
/// Usata sia nella HomePage utente ("Il mio abbonamento") sia nel dettaglio
/// utente lato Admin/Trainer ("Abbonamenti attivi"). Lo stile (sfondo scuro,
/// testo bianco) è allineato alla `CustomCard` già usata per l'abbonamento.
class ActiveSubscriptionCard extends StatelessWidget {
  final UserSubscription subscription;

  const ActiveSubscriptionCard({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    // Ingressi esauriti ma non scaduto: colore di attenzione (non verde), così
    // il colore concorda con lo stato "Esaurito" e con il blocco lato
    // getCourseState (SUBSCRIBE_LIMIT).
    final bool scaduto =
        AbbonamentoHelper.isAbbonamentoScaduto(subscription.endDate);
    final bool esaurito = !scaduto &&
        subscription.billingMode == BillingMode.ENTRIES &&
        (subscription.remainingEntries ?? 0) <= 0;
    final Color statoColor = esaurito
        ? warningColor
        : AbbonamentoHelper.getColoreScadenza(subscription.endDate);
    final String stato = getSubscriptionStatusLabel(subscription);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: onSurfaceColor,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            getSubscriptionTitle(subscription),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            getSubscriptionAllowanceLabel(subscription),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event, size: 16, color: statoColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${getSubscriptionExpiryLabel(subscription)} · $stato',
                  style: TextStyle(
                    color: statoColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
