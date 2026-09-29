import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/state/simulation_session.dart';

/// Esito di `assignSubscription`: id del nuovo abbonamento, delle eventuali
/// Prove V2 chiuse e sostituite, e se è stata sostituita una Prova V1.
typedef AssignSubscriptionResult = ({
  String subscriptionId,
  List<String> replacedTrialIds,
  bool replacedLegacyTrial,
});

/// Chiama la Cloud Function `assignSubscription` (solo Admin). [startDate] e
/// [endDate] sono istanti già convertiti (vedi `subscription_dates.dart`);
/// senza, il server usa ora e la durata del piano.
/// Propaga [FirebaseFunctionsException].
Future<AssignSubscriptionResult> assignSubscription({
  required String userId,
  required String planKey,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  SimulationSession.assertNotSimulating('assignSubscription');
  final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
      .httpsCallable('assignSubscription');
  final result = await callable.call(<String, dynamic>{
    'userId': userId,
    'planKey': planKey,
    if (startDate != null) 'startDateMillis': startDate.millisecondsSinceEpoch,
    if (endDate != null) 'endDateMillis': endDate.millisecondsSinceEpoch,
  });
  final data = Map<String, dynamic>.from(result.data as Map);
  return (
    subscriptionId: (data['subscriptionId'] as String?) ?? '',
    replacedTrialIds:
        ((data['replacedTrialIds'] as List?) ?? const []).cast<String>(),
    replacedLegacyTrial: data['replacedLegacyTrial'] == true,
  );
}
