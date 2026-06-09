import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/api/subscriptions/assign_subscription.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Card admin per assegnare un abbonamento a un utente (chiama la Cloud Function
/// `assignSubscription`). Self-contained: gestisce loading/errore/successo.
class AssignSubscriptionCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onAssigned;

  const AssignSubscriptionCard({
    super.key,
    required this.userId,
    this.onAssigned,
  });

  @override
  State<AssignSubscriptionCard> createState() => _AssignSubscriptionCardState();
}

class _AssignSubscriptionCardState extends State<AssignSubscriptionCard> {
  String? selectedPlanKey;
  bool loading = false;

  Future<void> _assign() async {
    final planKey = selectedPlanKey;
    if (planKey == null) return;
    setState(() => loading = true);
    try {
      await assignSubscription(userId: widget.userId, planKey: planKey);
      if (!mounted) return;
      SnackBarUtils.showSuccessSnackBar(context, 'Abbonamento assegnato');
      widget.onAssigned?.call();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      SnackBarUtils.showErrorSnackBar(
          context, e.message ?? 'Errore durante l\'assegnazione');
    } catch (_) {
      if (!mounted) return;
      SnackBarUtils.showErrorSnackBar(
          context, 'Errore durante l\'assegnazione dell\'abbonamento');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surfaceVariantColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assegna abbonamento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedPlanKey,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              hint: const Text('Seleziona un piano'),
              items: SubscriptionPlans.all
                  .map((p) => DropdownMenuItem<String>(
                        value: p.key,
                        child: Text(p.displayName,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged:
                  loading ? null : (v) => setState(() => selectedPlanKey = v),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (selectedPlanKey == null || loading) ? null : _assign,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryLightColor,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Assegna'),
            ),
          ],
        ),
      ),
    );
  }
}
