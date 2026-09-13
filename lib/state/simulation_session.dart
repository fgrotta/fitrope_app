import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/foundation.dart';

/// Errore lanciato da [SimulationSession.assertNotSimulating] quando un'azione
/// di scrittura viene tentata in modalità simulazione.
///
/// `toString()` ritorna SOLO il messaggio (niente prefisso "Exception:"), come
/// già fa `EnrollmentException`: i call site che interpolano `$e` in una
/// snackbar restano leggibili.
class SimulationBlockedException implements Exception {
  /// Nome dell'operazione bloccata (per i log, non per l'utente).
  final String operation;

  const SimulationBlockedException(this.operation);

  @override
  String toString() => 'Modalità simulazione: azione non eseguita.';
}

/// Identità coinvolte in una sessione di simulazione.
class SimulationInfo {
  /// L'Admin che sta simulando: serve per uscire e per la barra.
  final FitropeUser realUser;

  /// L'utente di cui si sta vedendo l'app.
  final FitropeUser simulatedUser;

  const SimulationInfo({required this.realUser, required this.simulatedUser});
}

/// Stato della modalità simulazione — un singleton in memoria, NON un campo di
/// `AppState`.
///
/// Perché fuori da Redux: `AppState` non ha `copyWith` e `appReducer` è una
/// if-chain che un quinto campo toccherebbe in tutti i rami; inoltre la
/// reattività Redux non servirebbe comunque, perché il cambio di identità forza
/// un remount completo (vedi `SimulationController`). Il [ValueNotifier] serve
/// solo alla barra, che vive nel `builder` di `MaterialApp`, fuori dal Navigator.
///
/// In simulazione `store.state.user` È l'utente simulato: è da lì che quasi
/// tutta la fedeltà visiva arriva gratis (`getCourseState`, i ~45 confronti
/// `role == 'Admin'`, le tab admin che spariscono).
///
/// Nessuna persistenza: un reload termina la simulazione.
class SimulationSession {
  SimulationSession._();

  /// Sessione corrente, `null` quando non si sta simulando.
  static final ValueNotifier<SimulationInfo?> current =
      ValueNotifier<SimulationInfo?>(null);

  static int _generation = 0;

  /// Incrementa a ogni cambio di identità — su `start` **e** su `stop`. Usata
  /// come `ValueKey` su `Protected` in `router.dart`: rinforzo a costo zero che
  /// garantisce uno `State` nuovo anche se un giorno il remount via
  /// `pushNamedAndRemoveUntil` venisse sostituito.
  static int get generation => _generation;

  static bool get isActive => current.value != null;

  /// Entra in simulazione. Non annidabile: simulare da dentro una simulazione
  /// falsificherebbe l'identità reale dell'admin da ripristinare all'uscita.
  static void start({required FitropeUser admin, required FitropeUser target}) {
    if (isActive) {
      throw StateError(
          'Simulazione già attiva: non è possibile annidare le simulazioni.');
    }
    _generation++;
    current.value = SimulationInfo(realUser: admin, simulatedUser: target);
  }

  /// Esce dalla simulazione. No-op se non è attiva (così può essere chiamata
  /// incondizionatamente, es. dal logout).
  static void stop() {
    if (!isActive) return;
    _generation++;
    current.value = null;
  }

  /// Rete di sicurezza del layer API (Layer B): lancia **anche in release**,
  /// perché il rischio non è un bug di sviluppo ma una scrittura vera in
  /// produzione sui dati di un socio.
  static void assertNotSimulating(String operation) {
    if (isActive) {
      debugPrint('⛔ [Simulazione] operazione bloccata: $operation');
      throw SimulationBlockedException(operation);
    }
  }
}
