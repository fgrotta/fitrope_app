import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/state/simulation_session.dart';

/// Completa idempotentemente la prova richiesta durante la self-registration.
/// Il server esegue un no-op per i profili che non hanno il marker pendente.
Future<void> grantSignupTrial() async {
  SimulationSession.assertNotSimulating('grantSignupTrial');
  await FirebaseFunctions.instanceFor(region: 'europe-west8')
      .httpsCallable('grantSignupTrial')
      .call();
}
