import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/state/simulation_session.dart';

Future<void> resetPassword(String email) async {
  SimulationSession.assertNotSimulating('resetPassword');
  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  } catch (e) {
    rethrow;
  }
}
