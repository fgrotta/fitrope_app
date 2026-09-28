import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Riga "etichetta + data" con selettore, per le date di un abbonamento
/// (assegnazione, modifica, creazione utente). La data è un giorno intero:
/// la conversione in istanti di Roma sta in `subscription_dates.dart`.
class SubscriptionDateRow extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;
  final bool enabled;
  final Key? buttonKey;

  const SubscriptionDateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
    this.enabled = true,
    this.buttonKey,
  });

  Future<void> _pick(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (selected != null) onPicked(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        OutlinedButton.icon(
          key: buttonKey,
          onPressed: enabled ? () => _pick(context) : null,
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(
            value == null ? '—' : DateFormat('dd/MM/yyyy').format(value!),
          ),
        ),
      ],
    );
  }
}
