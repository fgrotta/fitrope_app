import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/simulation_controller.dart';
import 'package:flutter/material.dart';

/// Barra fissa in alto che segnala la modalità simulazione.
///
/// Vive nel `builder` di `MaterialApp` (l'unico seam che avvolge il Navigator),
/// quindi copre **ogni** route pushata e resta sopra dialog ed `endDrawer`:
/// "Esci" è sempre raggiungibile, anche a dialog aperto.
///
/// A simulazione spenta ritorna il [child] **identico**: zero impatto sul layout
/// e nessuna regressione sulle pagine esistenti.
class SimulationBanner extends StatelessWidget {
  final Widget child;

  const SimulationBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SimulationInfo?>(
      valueListenable: SimulationSession.current,
      builder: (context, info, _) {
        if (info == null) return child;

        return Column(
          children: [
            _SimulationBar(info: info),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _SimulationBar extends StatelessWidget {
  final SimulationInfo info;

  const _SimulationBar({required this.info});

  @override
  Widget build(BuildContext context) {
    final user = info.simulatedUser;
    final nome = '${user.name} ${user.lastName}'.trim();
    // Il gate sui 600 vale sull'avvio, non sulla permanenza: la barra deve
    // reggere una finestra ristretta sotto i 600 durante la simulazione, senza
    // mai troncare via il bottone di uscita.
    final compatta = isMobile(context);

    // Niente SafeArea qui: `main.dart` avvolge già tutto in un SafeArea *sopra*
    // MaterialApp, quindi dentro `builder` il padding top è già consumato.
    return Material(
      color: warningColor,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compatta ? 8 : 16),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  compatta ? nome : 'Stai visualizzando l\'app come $nome',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (compatta)
                IconButton(
                  onPressed: () => SimulationController.stop(),
                  tooltip: 'Esci dalla simulazione',
                  color: Colors.white,
                  icon: const Icon(Icons.logout),
                )
              else
                TextButton.icon(
                  onPressed: () => SimulationController.stop(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Esci dalla simulazione'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
