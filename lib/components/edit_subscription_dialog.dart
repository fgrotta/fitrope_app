import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitrope_app/api/subscriptions/manage_subscription.dart';
import 'package:fitrope_app/components/subscription_date_row.dart';
import 'package:fitrope_app/components/subscription_plan_picker.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_dates.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

typedef UpdateSubscriptionFn = Future<void> Function({
  required String subscriptionId,
  required String planKey,
  required DateTime startDate,
  required DateTime endDate,
  int? remainingEntries,
  required int? expectedRemainingEntries,
});

/// Dialog Admin di modifica di un abbonamento: tipologia (piano), date e
/// ingressi residui. Ritorna `true` via `Navigator.pop` se il salvataggio è
/// riuscito. La guardia di simulazione sta nel callback della pagina che lo
/// apre; qui resta la rete di sicurezza dell'API.
class EditSubscriptionDialog extends StatefulWidget {
  final UserSubscription subscription;

  /// Iniettabile nei test; default: la callable reale.
  final UpdateSubscriptionFn? save;

  const EditSubscriptionDialog({
    super.key,
    required this.subscription,
    this.save,
  });

  @override
  State<EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  SubscriptionPlan? _plan;
  late DateTime _startDate;
  late DateTime _endDate;
  late final TextEditingController _entries;

  // Campi toccati a mano: un cambio di tipologia non li sovrascrive più.
  bool _endTouched = false;
  bool _entriesTouched = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.subscription;
    final plan = SubscriptionPlans.byKey(s.planKey);
    // La Prova non è una tipologia selezionabile: si parte senza piano.
    _plan = plan?.durationMonths == null ? null : plan;
    _startDate = romeDay(s.startDate);
    _endDate = romeDay(s.endDate);
    _entries =
        TextEditingController(text: s.remainingEntries?.toString() ?? '');
  }

  @override
  void dispose() {
    _entries.dispose();
    super.dispose();
  }

  void _onPlanChanged(SubscriptionPlan? plan) {
    setState(() {
      final changed = plan != null && plan.key != _plan?.key;
      _plan = plan;
      if (!changed) return;
      if (!_endTouched) _endDate = defaultEndDate(plan, _startDate);
      if (!_entriesTouched && plan.billingMode == BillingMode.ENTRIES) {
        _entries.text = '${plan.entries}';
      }
    });
  }

  bool get _isEntries => _plan?.billingMode == BillingMode.ENTRIES;

  int? get _entriesValue => int.tryParse(_entries.text.trim());

  /// Primo errore di validazione in linea, null se il modulo è valido.
  String? get _validationError {
    final plan = _plan;
    if (plan == null) return 'Seleziona la tipologia';
    if (_endDate.isBefore(_startDate)) {
      return 'La data di fine non può precedere la data di inizio';
    }
    // Nessun tetto: l'Admin può dare più ingressi di quelli del pacchetto.
    if (_isEntries && _entriesValue == null) {
      return 'Indica gli ingressi residui';
    }
    return null;
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || _validationError != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.save ?? updateSubscription)(
        subscriptionId: widget.subscription.id!,
        planKey: plan.key,
        startDate: subscriptionStartTimestamp(_startDate).toDate(),
        endDate: subscriptionEndTimestamp(_endDate).toDate(),
        remainingEntries: _isEntries ? _entriesValue : null,
        expectedRemainingEntries: widget.subscription.remainingEntries,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message ?? 'Modifica non riuscita';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Modifica non riuscita';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = _validationError;
    return AlertDialog(
      title: Text('Modifica ${getSubscriptionTitle(widget.subscription)}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubscriptionPlanPicker(
                initialPlanKey: widget.subscription.planKey,
                enabled: !_saving,
                onChanged: _onPlanChanged,
              ),
              const SizedBox(height: 12),
              SubscriptionDateRow(
                label: 'Data inizio',
                value: _startDate,
                enabled: !_saving,
                buttonKey: const Key('edit-start-date'),
                onPicked: (day) => setState(() => _startDate = day),
              ),
              const SizedBox(height: 6),
              SubscriptionDateRow(
                label: 'Data fine',
                value: _endDate,
                enabled: !_saving,
                buttonKey: const Key('edit-end-date'),
                onPicked: (day) => setState(() {
                  _endDate = day;
                  _endTouched = true;
                }),
              ),
              if (_isEntries) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('edit-remaining-entries'),
                  controller: _entries,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Ingressi residui',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _entriesTouched = true),
                ),
              ],
              if (validation != null || _error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error ?? validation!,
                  style: const TextStyle(color: errorColor),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const Key('edit-subscription-save'),
          onPressed: (_saving || validation != null) ? null : _save,
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
