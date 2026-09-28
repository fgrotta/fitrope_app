import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/types/user_subscription.dart';

HttpsCallable _callable(String name) =>
    FirebaseFunctions.instanceFor(region: 'europe-west8').httpsCallable(name);

/// Modifica un abbonamento (solo Admin, callable `updateSubscription`): piano,
/// date e ingressi residui (obbligatori solo per i piani a ingressi).
/// Propaga [FirebaseFunctionsException].
Future<void> updateSubscription({
  required String subscriptionId,
  required String planKey,
  required DateTime startDate,
  required DateTime endDate,
  int? remainingEntries,
}) async {
  SimulationSession.assertNotSimulating('updateSubscription');
  await _callable('updateSubscription').call(<String, dynamic>{
    'subscriptionId': subscriptionId,
    'planKey': planKey,
    'startDateMillis': startDate.millisecondsSinceEpoch,
    'endDateMillis': endDate.millisecondsSinceEpoch,
    if (remainingEntries != null) 'remainingEntries': remainingEntries,
  });
}

/// Revoca un abbonamento conservandone lo storico (solo Admin, callable
/// `revokeSubscription`). Ritorna true se era già revocato.
Future<bool> revokeSubscription(String subscriptionId) async {
  SimulationSession.assertNotSimulating('revokeSubscription');
  final result = await _callable('revokeSubscription').call(<String, dynamic>{
    'subscriptionId': subscriptionId,
  });
  final data = Map<String, dynamic>.from(result.data as Map);
  return data['alreadyRevoked'] == true;
}

/// Tutti i documenti `subscriptions` dell'utente — in corso, futuri, scaduti e
/// revocati — per lo storico Admin. Le rules consentono la lettura all'Admin.
Future<List<UserSubscription>> getUserSubscriptions(
  String userId, {
  FirebaseFirestore? firestore,
}) async {
  final snap = await (firestore ?? FirebaseFirestore.instance)
      .collection('subscriptions')
      .where('userId', isEqualTo: userId)
      .get();
  return snap.docs
      .map((doc) => UserSubscription.fromJson({...doc.data(), 'id': doc.id}))
      .toList();
}
