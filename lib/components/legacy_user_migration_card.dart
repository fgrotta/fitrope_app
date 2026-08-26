import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/api/subscriptions/legacy_user_migration.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fitrope_app/layout/breakpoints.dart';

typedef LegacyPreview = Future<Map<String, dynamic>> Function(String userId);
typedef LegacyAutoMigration = Future<Map<String, dynamic>> Function(
  String userId,
  String fingerprint,
);
typedef LegacyGuidedMigration = Future<Map<String, dynamic>> Function(
  String userId,
  String fingerprint,
  String planKey,
  DateTime startDate,
  DateTime endDate,
  int? remainingEntries,
);

bool shouldShowLegacyUserMigration(BuildContext context, String? role) =>
    role == 'Admin' && isDesktop(context);

/// Conversione controllata del modello abbonamento legacy. Il parent decide
/// visibilità per ruolo e breakpoint; la card nasconde gli stati già migrati o
/// non applicabili e mantiene i conflitti in sola lettura.
class LegacyUserMigrationCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onMigrated;
  final LegacyPreview? preview;
  final LegacyAutoMigration? migrateAuto;
  final LegacyGuidedMigration? migrateGuided;

  const LegacyUserMigrationCard({
    super.key,
    required this.userId,
    this.onMigrated,
    this.preview,
    this.migrateAuto,
    this.migrateGuided,
  });

  @override
  State<LegacyUserMigrationCard> createState() =>
      _LegacyUserMigrationCardState();
}

class _LegacyUserMigrationCardState extends State<LegacyUserMigrationCard> {
  Map<String, dynamic>? _preview;
  bool _loading = true;
  bool _applying = false;
  String? _error;
  SubscriptionPlan? _plan;
  DateTime? _startDate;
  DateTime? _endDate;
  final _remainingEntries = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _remainingEntries.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final result = await (widget.preview ?? LegacyUserMigrationApi.preview)(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _preview = result;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossibile caricare l\'anteprima della migrazione';
      });
    }
  }

  Future<void> _applyAuto() async {
    final fingerprint = _preview?['expectedFingerprint'] as String?;
    if (fingerprint == null) return;
    if (!await _confirm()) return;
    await _run(() async {
      final operation = widget.migrateAuto ??
          (String userId, String expected) =>
              LegacyUserMigrationApi.migrateAuto(
                userId: userId,
                expectedFingerprint: expected,
              );
      await operation(widget.userId, fingerprint);
    });
  }

  Future<void> _applyGuided() async {
    final fingerprint = _preview?['expectedFingerprint'] as String?;
    final plan = _plan;
    final start = _startDate;
    final end = _endDate;
    final remaining = int.tryParse(_remainingEntries.text.trim());
    if (fingerprint == null || plan == null || start == null || end == null) {
      setState(() => _error = 'Seleziona piano, data iniziale e data finale');
      return;
    }
    if (plan.billingMode == BillingMode.ENTRIES && remaining == null) {
      setState(() => _error = 'Indica gli ingressi residui');
      return;
    }
    if (!await _confirm()) return;
    await _run(() async {
      final operation = widget.migrateGuided ??
          (
            String userId,
            String expected,
            String planKey,
            DateTime startDate,
            DateTime endDate,
            int? remainingEntries,
          ) =>
              LegacyUserMigrationApi.migrateGuided(
                userId: userId,
                expectedFingerprint: expected,
                planKey: planKey,
                startDate: startDate,
                endDate: endDate,
                remainingEntries: remainingEntries,
              );
      await operation(
        widget.userId,
        fingerprint,
        plan.key,
        start,
        end,
        remaining,
      );
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await operation();
      if (!mounted) return;
      setState(() {
        _applying = false;
        _preview = <String, dynamic>{'status': 'MIGRATED'};
      });
      SnackBarUtils.showSuccessSnackBar(context, 'Abbonamento legacy migrato');
      widget.onMigrated?.call();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = error.message ?? 'Migrazione non riuscita';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = 'Migrazione non riuscita';
      });
    }
  }

  Future<bool> _confirm() async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Conferma migrazione'),
          content: const Text(
            'La conversione crea un nuovo abbonamento e non modifica lo storico delle iscrizioni. Continuare?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Migra'),
            ),
          ],
        ),
      )) ??
      false;

  Future<void> _pickDate({required bool start}) async {
    final initial = start
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now().add(const Duration(days: 30)));
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  String _legacySummary() {
    final legacy = Map<String, dynamic>.from(
      (_preview?['legacy'] as Map?) ?? const {},
    );
    final endMillis = legacy['fineIscrizione'] as num?;
    final end = endMillis == null
        ? 'non impostata'
        : DateFormat('dd/MM/yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(endMillis.toInt()),
          );
    return 'Legacy: ${legacy['tipologiaIscrizione'] ?? 'non definito'} · '
        '${legacy['entrateSettimanali'] ?? '—'} ingressi/settimana · scadenza $end';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }
    final status = _preview?['status'] as String?;
    if (status == 'MIGRATED' || status == 'NOT_APPLICABLE') {
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('legacy-user-migration-card'),
      color: surfaceVariantColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Migrazione abbonamento legacy',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_legacySummary()),
            const SizedBox(height: 8),
            if (status == 'CONFLICT')
              Text(
                _preview?['reasonDetail'] as String? ??
                    'Esiste già un abbonamento della stessa famiglia.',
                style: const TextStyle(color: warningColor),
              ),
            if (status == 'AUTO_CONVERTIBLE') ...[
              Text(
                'Target: ${(_preview?['target'] as Map?)?['planKey']}',
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('legacy-migration-auto'),
                onPressed: _applying ? null : _applyAuto,
                child: const Text('Migra automaticamente'),
              ),
            ],
            if (status == 'MANUAL_REQUIRED') ...[
              DropdownButtonFormField<SubscriptionPlan>(
                key: const Key('legacy-migration-plan'),
                initialValue: _plan,
                decoration: const InputDecoration(labelText: 'Piano target'),
                items: SubscriptionPlans.all
                    .map(
                      (plan) => DropdownMenuItem(
                        value: plan,
                        child: Text(plan.displayName),
                      ),
                    )
                    .toList(),
                onChanged:
                    _applying ? null : (value) => setState(() => _plan = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _applying ? null : () => _pickDate(start: true),
                    child: Text(
                      _startDate == null
                          ? 'Data inizio'
                          : DateFormat('dd/MM/yyyy').format(_startDate!),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _applying ? null : () => _pickDate(start: false),
                    child: Text(
                      _endDate == null
                          ? 'Data fine'
                          : DateFormat('dd/MM/yyyy').format(_endDate!),
                    ),
                  ),
                ],
              ),
              if (_plan?.billingMode == BillingMode.ENTRIES) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _remainingEntries,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ingressi residui',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('legacy-migration-guided'),
                onPressed: _applying ? null : _applyGuided,
                child: const Text('Migra con piano scelto'),
              ),
            ],
            if (_applying) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: errorColor)),
            ],
          ],
        ),
      ),
    );
  }
}
