import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/api/subscriptions/assign_subscription.dart';
import 'package:fitrope_app/components/subscription_date_row.dart';
import 'package:fitrope_app/components/subscription_plan_picker.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/simulation_guard.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/subscription_dates.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/types/user_subscription.dart';

typedef AssignSubscriptionFn = Future<AssignSubscriptionResult> Function({
  required String userId,
  required String planKey,
  DateTime? startDate,
  DateTime? endDate,
});

/// Card admin per assegnare un abbonamento a un utente (chiama la Cloud Function
/// `assignSubscription`). Self-contained: gestisce loading/errore/successo.
class AssignSubscriptionCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onAssigned;

  /// Abbonamenti dell'utente: servono solo per l'avviso di sostituzione della
  /// Prova (il server resta l'autorità sui conflitti).
  final List<UserSubscription> subscriptions;

  /// Prova sul modello legacy (V1): anche questa viene chiusa e sostituita.
  final bool hasLegacyTrial;

  /// Iniettabili nei test; default: la callable reale e la data di oggi.
  final AssignSubscriptionFn? assign;
  final DateTime? today;

  const AssignSubscriptionCard({
    super.key,
    required this.userId,
    this.onAssigned,
    this.subscriptions = const [],
    this.hasLegacyTrial = false,
    this.assign,
    this.today,
  });

  @override
  State<AssignSubscriptionCard> createState() => _AssignSubscriptionCardState();
}

class _AssignSubscriptionCardState extends State<AssignSubscriptionCard> {
  SubscriptionPlan? _plan;
  late DateTime _startDate;

  /// Fine scelta a mano dall'Admin: finché è null la fine segue piano + inizio.
  DateTime? _manualEndDate;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    final now = widget.today ?? DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
  }

  DateTime? get _endDate =>
      _manualEndDate ??
      (_plan == null ? null : defaultEndDate(_plan!, _startDate));

  bool get _windowValid {
    final end = _endDate;
    return end != null && !end.isBefore(_startDate);
  }

  bool get _replacesTrial {
    if (_plan?.family != SubscriptionFamily.OPEN) return false;
    if (widget.hasLegacyTrial) return true;
    final start = subscriptionStartTimestamp(_startDate).toDate();
    return widget.subscriptions.any(
      (s) =>
          s.planKey == SubscriptionPlans.trial.key &&
          !s.isRevoked &&
          !s.endDate.toDate().isBefore(start),
    );
  }

  Future<void> _assign() async {
    if (SimulationGuard.blockIfSimulating(context)) return;
    final plan = _plan;
    final end = _endDate;
    if (plan == null || end == null || !_windowValid) return;
    setState(() => loading = true);
    try {
      final result = await (widget.assign ?? assignSubscription)(
        userId: widget.userId,
        planKey: plan.key,
        startDate: subscriptionStartTimestamp(_startDate).toDate(),
        endDate: subscriptionEndTimestamp(end).toDate(),
      );
      if (!mounted) return;
      SnackBarUtils.showSuccessSnackBar(
        context,
        result.replacedTrialIds.isEmpty
            ? 'Abbonamento assegnato'
            : 'Abbonamento assegnato. Prova chiusa e sostituita',
      );
      widget.onAssigned?.call();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      SnackBarUtils.showErrorSnackBar(
        context,
        e.message ?? 'Errore durante l\'assegnazione',
      );
    } catch (_) {
      if (!mounted) return;
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante l\'assegnazione dell\'abbonamento',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final end = _endDate;
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
            SubscriptionPlanPicker(
              enabled: !loading,
              onChanged: (plan) => setState(() => _plan = plan),
            ),
            const SizedBox(height: 12),
            SubscriptionDateRow(
              label: 'Data inizio',
              value: _startDate,
              enabled: !loading,
              buttonKey: const Key('assign-start-date'),
              onPicked: (day) => setState(() => _startDate = day),
            ),
            const SizedBox(height: 6),
            SubscriptionDateRow(
              label: 'Data fine',
              value: end,
              enabled: !loading && _plan != null,
              buttonKey: const Key('assign-end-date'),
              onPicked: (day) => setState(() => _manualEndDate = day),
            ),
            if (end != null && !_windowValid) ...[
              const SizedBox(height: 6),
              const Text(
                'La data di fine non può precedere la data di inizio',
                style: TextStyle(color: errorColor),
              ),
            ],
            if (_replacesTrial) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: warningColor),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'La Prova verrà chiusa e sostituita da questo abbonamento',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (!_windowValid || loading) ? null : _assign,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryLightColor,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Assegna'),
            ),
          ],
        ),
      ),
    );
  }
}
