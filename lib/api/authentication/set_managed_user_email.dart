import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/utils/email_validation.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

Future<void> setManagedUserEmail({
  required String userId,
  required String email,
}) async {
  SimulationSession.assertNotSimulating('setManagedUserEmail');
  await FirebaseFunctions.instanceFor(
    region: 'europe-west8',
  ).httpsCallable('setManagedUserEmail').call(<String, dynamic>{
    'userId': userId,
    'email': EmailValidation.normalize(email),
  });
  invalidateAllUserCaches();
}
