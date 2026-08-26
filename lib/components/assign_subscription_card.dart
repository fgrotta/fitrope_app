import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/api/subscriptions/assign_subscription.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/types/user_subscription.dart';

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
  SubscriptionFamily? selectedFamily;
  BillingMode? selectedBillingMode;
  String? selectedVariant;
  int? selectedDuration;
  bool loading = false;

  List<SubscriptionPlan> get _familyPlans => selectedFamily == null
      ? const []
      : SubscriptionPlans.all
          .where((plan) => plan.family == selectedFamily)
          .toList();

  List<SubscriptionPlan> get _modePlans => selectedBillingMode == null
      ? const []
      : _familyPlans
          .where((plan) => plan.billingMode == selectedBillingMode)
          .toList();

  String _variantOf(SubscriptionPlan plan) =>
      plan.billingMode == BillingMode.ENTRIES
          ? '${plan.entries}i'
          : plan.weeklyFrequency == null
              ? 'unlim'
              : '${plan.weeklyFrequency}x';

  String _variantLabel(String value) {
    if (value == 'unlim') return 'Illimitato';
    if (value.endsWith('i')) {
      return '${value.substring(0, value.length - 1)} ingressi';
    }
    return '${value.substring(0, value.length - 1)} volte/settimana';
  }

  String? get selectedPlanKey {
    if (selectedVariant == null || selectedDuration == null) return null;
    return _modePlans
        .where((plan) =>
            _variantOf(plan) == selectedVariant &&
            plan.durationMonths == selectedDuration)
        .firstOrNull
        ?.key;
  }

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
            _dropdown<SubscriptionFamily>(
              label: 'Tipo',
              value: selectedFamily,
              values: SubscriptionFamily.values,
              text: (value) => value == SubscriptionFamily.OPEN
                  ? 'Open'
                  : 'Personal Trainer',
              onChanged: (value) => setState(() {
                selectedFamily = value;
                selectedBillingMode = null;
                selectedVariant = null;
                selectedDuration = null;
              }),
            ),
            const SizedBox(height: 10),
            _dropdown<BillingMode>(
              label: 'Modalita',
              value: selectedBillingMode,
              values: _familyPlans.map((plan) => plan.billingMode).toSet(),
              text: (value) => value == BillingMode.FREQUENCY
                  ? 'Frequenza settimanale'
                  : 'Pacchetto ingressi',
              onChanged: selectedFamily == null
                  ? null
                  : (value) => setState(() {
                        selectedBillingMode = value;
                        selectedVariant = null;
                        selectedDuration = null;
                      }),
            ),
            const SizedBox(height: 10),
            _dropdown<String>(
              label: 'Variante',
              value: selectedVariant,
              values: _modePlans.map(_variantOf).toSet(),
              text: _variantLabel,
              onChanged: selectedBillingMode == null
                  ? null
                  : (value) => setState(() {
                        selectedVariant = value;
                        selectedDuration = null;
                      }),
            ),
            const SizedBox(height: 10),
            _dropdown<int>(
              label: 'Durata',
              value: selectedDuration,
              values: selectedVariant == null
                  ? const <int>{}
                  : _modePlans
                      .where((plan) => _variantOf(plan) == selectedVariant)
                      .map((plan) => plan.durationMonths)
                      .toSet(),
              text: (value) => value == 1 ? '1 mese' : '$value mesi',
              onChanged: selectedVariant == null
                  ? null
                  : (value) => setState(() => selectedDuration = value),
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

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required Iterable<T> values,
    required String Function(T) text,
    required ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: values
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(text(item), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: loading ? null : onChanged,
    );
  }
}
