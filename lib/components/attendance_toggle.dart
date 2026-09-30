import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/utils/attendance_window.dart';
import 'package:flutter/material.dart';

/// Spunta "Presente" per una riga dell'appello. Un FilterChip e non una
/// Checkbox/Switch: in palestra, col telefono in mano, serve un'area di tocco
/// ampia (48 px) e un'etichetta leggibile.
class AttendanceToggle extends StatelessWidget {
  final AttendanceRecord? record;

  /// Richiesta in volo (o presenze in caricamento): spinner, tocco disattivato.
  final bool pending;

  /// Riceve il nuovo valore di `present` richiesto.
  final ValueChanged<bool>? onChanged;

  const AttendanceToggle({
    super.key,
    required this.record,
    this.pending = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final present = isMarkedPresent(record);
    final selfDeclared =
        present && record?.source == AttendanceSource.self && !pending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FilterChip(
          label: const Text('Presente'),
          selected: present,
          showCheckmark: !pending,
          avatar: pending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          selectedColor: const Color(0xFFC8E6C9),
          onSelected:
              pending || onChanged == null ? null : (_) => onChanged!(!present),
        ),
        if (selfDeclared)
          const Text(
            'dichiarata dal socio',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
      ],
    );
  }
}
