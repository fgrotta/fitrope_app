// ignore_for_file: avoid_print
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

class SignInResponse {
  final FitropeUser? user;
  final String error;

  SignInResponse({
    this.user,
    required this.error
  });
}

Future<SignInResponse> signInWithEmailPassword(String email, String password) async {
  store.dispatch(StartLoadingAction());
  try {
    UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    print("User signed in: ${userCredential.user!.email}");

    if(userCredential.user != null) {
      String uid = userCredential.user!.uid;
      Map<String, dynamic>? userData = await getUserData(uid);

      store.dispatch(FinishLoadingAction());

      if(userData != null) {
        return SignInResponse(user: FitropeUser.fromJson(userData), error: "");
      }

      return SignInResponse(error: "Email o password sbagliati");
    }
  } 
  on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      print('No user found for that email.');
    } 
    else if (e.code == 'wrong-password') {
      print('Wrong password provided.');
    } 
    else {
      print(e.message);
    }
  } 
  catch (e) {
    print(e);
  }

  store.dispatch(FinishLoadingAction());
  return SignInResponse(error: "Email o password sbagliati");
}
