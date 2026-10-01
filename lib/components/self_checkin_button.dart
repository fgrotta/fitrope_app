import 'package:fitrope_app/utils/attendance_window.dart';
import 'package:flutter/material.dart';

/// Check-in del socio sulla card del corso: un solo widget per tutti gli
/// stati di [SelfCheckInState]. Gli stati "avviso" ([isNotice]) vanno messi a
/// tutta larghezza sotto la riga azioni; gli altri stanno nella riga.
class SelfCheckInButton extends StatefulWidget {
  final SelfCheckInState state;

  /// Ritorna true se il check-in è andato a buon fine.
  final Future<bool> Function()? onCheckIn;

  const SelfCheckInButton({super.key, required this.state, this.onCheckIn});

  /// Verde con contrasto AA sul testo bianco.
  static const Color presentColor = Color(0xFF2E7D32);

  static bool isNotice(SelfCheckInState state) =>
      state == SelfCheckInState.closedAskTrainer ||
      state == SelfCheckInState.absentStaff;

  @override
  State<SelfCheckInButton> createState() => _SelfCheckInButtonState();
}

class _SelfCheckInButtonState extends State<SelfCheckInButton> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    switch (widget.state) {
      case SelfCheckInState.notYetOpen:
        return const SizedBox.shrink();
      case SelfCheckInState.open:
        return _button();
      case SelfCheckInState.presentSelf:
        return _pill('Presente');
      case SelfCheckInState.presentStaff:
        return _pill('Presenza registrata');
      case SelfCheckInState.closedAskTrainer:
        // Avviso inline e non un dialog: un dialog scatterebbe a ogni rebuild.
        return _notice(
          'Check-in chiuso: chiedi al trainer di registrare la tua presenza',
          icon: Icons.info_outline,
          color: const Color(0xFFFFE0B2),
          textColor: const Color(0xFF7A4100),
        );
      case SelfCheckInState.absentStaff:
        return _notice(
          'Risulti assente. Se eri in sala, chiedi al trainer di correggere',
          icon: Icons.person_off_outlined,
          color: const Color(0xFFFFEBEE),
          textColor: const Color(0xFFB71C1C),
        );
    }
  }

  Widget _button() {
    return ElevatedButton.icon(
      key: const Key('self-checkin-button'),
      onPressed: widget.onCheckIn != null && !_isProcessing
          ? () async {
              setState(() => _isProcessing = true);
              try {
                await widget.onCheckIn!();
              } finally {
                if (mounted) setState(() => _isProcessing = false);
              }
            }
          : null,
      icon: const Icon(Icons.how_to_reg, color: Colors.white, size: 18),
      label: const Text('Sono in sala', style: TextStyle(color: Colors.white)),
      style: ButtonStyle(
        backgroundColor:
            WidgetStateProperty.all(SelfCheckInButton.presentColor),
        minimumSize: WidgetStateProperty.all(Size.zero),
        padding: WidgetStateProperty.all(const EdgeInsets.all(10)),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SelfCheckInButton.presentColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(
    String text, {
    required IconData icon,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
