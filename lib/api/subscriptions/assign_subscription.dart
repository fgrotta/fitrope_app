import 'package:cloud_functions/cloud_functions.dart';

/// Chiama la Cloud Function `assignSubscription` (solo Admin).
/// Ritorna l'id del nuovo abbonamento. Propaga [FirebaseFunctionsException].
Future<String> assignSubscription({
  required String userId,
  required String planKey,
  DateTime? startDate,
}) async {
  final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
      .httpsCallable('assignSubscription');
  final result = await callable.call(<String, dynamic>{
    'userId': userId,
    'planKey': planKey,
    if (startDate != null) 'startDateMillis': startDate.millisecondsSinceEpoch,
  });
  final data = Map<String, dynamic>.from(result.data as Map);
  return (data['subscriptionId'] as String?) ?? '';
}
