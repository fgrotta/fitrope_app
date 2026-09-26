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

/// Il login chiama [grantSignupTrial] solo se il profilo appena letto ha il
/// marker create-only della self-registration: per tutti gli altri il server
/// risponderebbe `NOT_PENDING`, dopo un round-trip (cold start incluso) che
/// teneva fermo il form.
bool needsSignupTrialGrant(Map<String, dynamic> userData) =>
    userData['signupTrialRequested'] == true;
