import 'package:fitrope_app/types/attendance_record.dart';
import 'package:flutter/material.dart';

/// Spunta dell'appello per una riga iscritto. Tre stati distinti a colpo
/// d'occhio: non segnato (contorno, cerchio vuoto), presente (verde pieno) e
/// assente registrato (rosso tenue). Il tocco alterna presente/assente.
///
/// Larghezza fissa, così cambiare stato non sposta il nome della riga, e area
/// di tocco di 48 px: in palestra si usa col telefono in mano.
class AttendanceToggle extends StatelessWidget {
  final AttendanceRecord? record;

  /// Richiesta in volo (o presenze in caricamento): spinner, tocco disattivato.
  final bool pending;

  /// Riceve il nuovo valore di `present` richiesto.
  final ValueChanged<bool>? onChanged;

  /// Etichetta per gli screen reader (es. "Mario Rossi: assente"): senza il
  /// nome un appello da 15 righe sarebbe 15 bottoni "Presente" identici.
  final String? semanticsLabel;

  const AttendanceToggle({
    super.key,
    required this.record,
    this.pending = false,
    this.onChanged,
    this.semanticsLabel,
  });

  static const double width = 112;

  static const Color _presentColor = Color(0xFF2E7D32);
  static const Color _absentBg = Color(0xFFFFEBEE);
  static const Color _absentFg = Color(0xFFB71C1C);
  static const Color _absentBorder = Color(0xFFE57373);
  static const Color _neutralFg = Color(0xFF37474F);
  // blueGrey 500: 3:1 sul bianco (il 300 di prima era 2.6:1).
  static const Color _neutralBorder = Color(0xFF607D8B);

  @override
  Widget build(BuildContext context) {
    final present = record?.present == true;
    final absent = record != null && !present;
    final enabled = !pending && onChanged != null;

    final Color background;
    final Color foreground;
    final Color border;
    final IconData icon;
    final String label;
    if (present) {
      background = _presentColor;
      foreground = Colors.white;
      border = _presentColor;
      icon = Icons.check;
      label = 'Presente';
    } else if (absent) {
      background = _absentBg;
      foreground = _absentFg;
      border = _absentBorder;
      icon = Icons.close;
      label = 'Assente';
    } else {
      background = Colors.white;
      foreground = _neutralFg;
      border = _neutralBorder;
      icon = Icons.radio_button_unchecked;
      label = 'Presente';
    }

    final shape = StadiumBorder(side: BorderSide(color: border, width: 1.5));
    return Semantics(
      button: true,
      toggled: present,
      enabled: enabled,
      label: semanticsLabel ?? (record == null ? 'Non segnato' : label),
      hint:
          present ? 'Tocca per segnare assente' : 'Tocca per segnare presente',
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!present) : null,
      child: SizedBox(
        width: width,
        height: 48,
        child: Center(
          child: Opacity(
            opacity: pending ? 0.7 : 1,
            child: Material(
              color: background,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: shape,
                onTap: enabled ? () => onChanged!(!present) : null,
                child: SizedBox(
                  width: width,
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: pending
                            ? CircularProgressIndicator(
                                strokeWidth: 2,
                                color: foreground,
                              )
                            : Icon(icon, size: 16, color: foreground),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
