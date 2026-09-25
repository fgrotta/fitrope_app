// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/get_user_data.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';
import 'package:fitrope_app/api/subscriptions/signup_trial.dart';
import 'package:fitrope_app/api/authentication/check_email_availability.dart';
import 'package:fitrope_app/utils/email_validation.dart';

class SignUpResponse {
  final FitropeUser? user;
  final String? error;

  SignUpResponse({this.user, this.error});
}

Future<SignUpResponse> registerWithEmailPassword(
  String email,
  String password,
  String name,
  String lastName, {
  String? numeroTelefono,
}) async {
  SimulationSession.assertNotSimulating('registerWithEmailPassword');
  try {
    final normalizedEmail = EmailValidation.normalize(email);
    if (!await checkEmailAvailability(normalizedEmail)) {
      return SignUpResponse(error: EmailValidation.duplicateProfileMessage);
    }
    UserCredential userCredential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    String uid = userCredential.user!.uid;

    // La prova viene concessa dalla callable, non dal client. Il marker e'
    // ammesso esclusivamente alla create e rende sicuro il retry al login.
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'email': normalizedEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'name': name,
      'lastName': lastName,
      'courses': [],
      'role': 'User',
      'numeroTelefono': numeroTelefono,
      'isActive': true,
      'isAnonymous': false,
      'emailNotificationsEnabled': true,
      'pushNotificationsEnabled': true,
      'signupTrialRequested': true,
    });

    // Invalida tutte le cache degli utenti dopo la registrazione
    invalidateAllUserCaches();

    // La registrazione Auth + profilo e' gia riuscita: un errore transient della
    // callable non deve presentarla come fallita. Il marker restera' pendente e
    // verra' ritentato al primo login.
    try {
      await grantSignupTrial();
    } catch (error) {
      print('Prova signup pendente (retry al login): $error');
    }

    await userCredential.user!.sendEmailVerification();
    print("Email di verifica inviata a $normalizedEmail");

    Map<String, dynamic>? userData = await getUserData(uid);

    if (userData != null) {
      return SignUpResponse(user: FitropeUser.fromJson(userData));
    }

    print("User registered: ${userCredential.user!.email}");
  } on FirebaseAuthException catch (e) {
    if (e.code == 'weak-password') {
      return SignUpResponse(error: 'The password is too weak');
    } else if (e.code == 'email-already-in-use') {
      return SignUpResponse(error: EmailValidation.duplicateAccountMessage);
    } else {
      return SignUpResponse(error: e.message);
    }
  } catch (e) {
    print(e);
  }

  return SignUpResponse(error: 'Error');
}
