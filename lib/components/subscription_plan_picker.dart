import 'package:flutter/material.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Selettore a cascata del piano (Tipo → Modalità → Variante → Durata), usato
/// dall'assegnazione e dalla modifica di un abbonamento. Offre solo i piani a
/// mesi: la Prova non è assegnabile dall'Admin.
///
/// [initialPlanKey] preseleziona il piano (dialog di modifica); una Prova
/// preseleziona solo la famiglia, perché non è tra le opzioni.
class SubscriptionPlanPicker extends StatefulWidget {
  final String? initialPlanKey;

  /// Chiamato a ogni cambio: il piano completo, oppure null finché la cascata
  /// non è completa.
  final ValueChanged<SubscriptionPlan?> onChanged;
  final bool enabled;

  const SubscriptionPlanPicker({
    super.key,
    this.initialPlanKey,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SubscriptionPlanPicker> createState() => _SubscriptionPlanPickerState();
}

/// Variante di un piano nella cascata: `10i`, `unlim`, `2x`, `3x`.
String subscriptionPlanVariant(SubscriptionPlan plan) =>
    plan.billingMode == BillingMode.ENTRIES
        ? '${plan.entries}i'
        : plan.weeklyFrequency == null
            ? 'unlim'
            : '${plan.weeklyFrequency}x';

class _SubscriptionPlanPickerState extends State<SubscriptionPlanPicker> {
  SubscriptionFamily? selectedFamily;
  BillingMode? selectedBillingMode;
  String? selectedVariant;
  int? selectedDuration;

  @override
  void initState() {
    super.initState();
    final key = widget.initialPlanKey;
    final plan = key == null ? null : SubscriptionPlans.byKey(key);
    if (plan == null) return;
    selectedFamily = plan.family;
    if (plan.durationMonths == null) return;
    selectedBillingMode = plan.billingMode;
    selectedVariant = subscriptionPlanVariant(plan);
    selectedDuration = plan.durationMonths;
  }

  List<SubscriptionPlan> get _familyPlans => selectedFamily == null
      ? const []
      : SubscriptionPlans.all
          .where(
            (plan) =>
                plan.family == selectedFamily && plan.durationMonths != null,
          )
          .toList();

  List<SubscriptionPlan> get _modePlans => selectedBillingMode == null
      ? const []
      : _familyPlans
          .where((plan) => plan.billingMode == selectedBillingMode)
          .toList();

  String _variantLabel(String value) {
    if (value == 'unlim') return 'Illimitato';
    if (value.endsWith('i')) {
      return '${value.substring(0, value.length - 1)} ingressi';
    }
    return '${value.substring(0, value.length - 1)} volte/settimana';
  }

  SubscriptionPlan? get _selectedPlan {
    if (selectedVariant == null || selectedDuration == null) return null;
    return _modePlans
        .where(
          (plan) =>
              subscriptionPlanVariant(plan) == selectedVariant &&
              plan.durationMonths == selectedDuration,
        )
        .firstOrNull;
  }

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(_selectedPlan);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown<SubscriptionFamily>(
          label: 'Tipo',
          value: selectedFamily,
          values: SubscriptionFamily.values,
          text: (value) =>
              value == SubscriptionFamily.OPEN ? 'Open' : 'Personal Trainer',
          onChanged: (value) => _update(() {
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
              : (value) => _update(() {
                    selectedBillingMode = value;
                    selectedVariant = null;
                    selectedDuration = null;
                  }),
        ),
        const SizedBox(height: 10),
        _dropdown<String>(
          label: 'Variante',
          value: selectedVariant,
          values: _modePlans.map(subscriptionPlanVariant).toSet(),
          text: _variantLabel,
          onChanged: selectedBillingMode == null
              ? null
              : (value) => _update(() {
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
                  .where(
                    (plan) => subscriptionPlanVariant(plan) == selectedVariant,
                  )
                  .map((plan) => plan.durationMonths!)
                  .toSet(),
          text: (value) => value == 1 ? '1 mese' : '$value mesi',
          onChanged: selectedVariant == null
              ? null
              : (value) => _update(() => selectedDuration = value),
        ),
      ],
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
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(text(item), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: widget.enabled ? onChanged : null,
    );
  }
}
