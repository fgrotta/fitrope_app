import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/utils/email_validation.dart';

Future<bool> checkEmailAvailability(String email) async {
  final result = await FirebaseFunctions.instanceFor(region: 'europe-west8')
      .httpsCallable('checkEmailAvailability')
      .call(<String, dynamic>{'email': EmailValidation.normalize(email)});
  return (result.data as Map)['available'] == true;
}
