import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';

/// Layer A della modalità simulazione — la guardia **di UX**.
///
/// Va messa come **prima istruzione** dei callback delle *pagine*, non dentro i
/// componenti: i tap handler stanno lì (`CourseCard` fa solo
/// `widget.onClickAction!()`), quindi la card continua a calcolare il proprio
/// `CourseState` e resta **colorata e cliccabile**. È esattamente il
/// comportamento voluto — vedere *se* il bottone sarebbe premibile è metà del
/// valore diagnostico — ottenuto senza toccare i componenti.
///
/// Il Layer B (`SimulationSession.assertNotSimulating` nel layer API) resta la
/// rete di sicurezza per i punti non inventariati.
class SimulationGuard {
  SimulationGuard._();

  /// Ritorna **true se l'azione è BLOCCATA**: il chiamante deve uscire subito.
  ///
  /// Passare il `context` della *pagina*, non quello di un dialog che sta per
  /// essere `pop`-pato: lo `ScaffoldMessenger` del dialog se ne andrebbe con
  /// lui e la snackbar non comparirebbe.
  static bool blockIfSimulating(BuildContext context) {
    if (!SimulationSession.isActive) return false;

    SnackBarUtils.showWarningSnackBar(context, kSimulationBlockedMessage);
    return true;
  }
}
