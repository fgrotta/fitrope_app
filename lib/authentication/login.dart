// ignore_for_file: avoid_print
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

class SignInResponse {
  final FitropeUser? user;
  final String error;
  final bool emailNotVerified;

  SignInResponse({
    this.user,
    required this.error,
    this.emailNotVerified = false,
  });
}

Future<SignInResponse> signInWithEmailPassword(
    String email, String password) async {
  store.dispatch(StartLoadingAction());
  try {
    UserCredential userCredential =
        await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = userCredential.user;

    if (user != null) {
      if (!user.emailVerified) {
        store.dispatch(FinishLoadingAction());
        print('Email non verificata.');
        return SignInResponse(
            error:
                "Email non verificata. Controlla la tua casella di posta per il link di verifica.",
            emailNotVerified: true);
      }

      print("User signed in: ${user.email}");

      String uid = user.uid;
      Map<String, dynamic>? userData = await getUserData(uid);

      store.dispatch(FinishLoadingAction());

      if (userData != null) {
        final fitropeUser = FitropeUser.fromJson(userData);

        // Controlla se l'utente è attivo
        if (!fitropeUser.isActive) {
          // Disconnetti l'utente da Firebase Auth
          await FirebaseAuth.instance.signOut();
          return SignInResponse(
              error:
                  "Il tuo account è stato disattivato. Contatta l'amministratore per maggiori informazioni.");
        }

        return SignInResponse(user: fitropeUser, error: "");
      }

      return SignInResponse(error: "Email o password sbagliati");
    }
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      print('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      print('Wrong password provided.');
    } else {
      print(e.message);
    }
  } catch (e) {
    print(e);
  }

  store.dispatch(FinishLoadingAction());
  return SignInResponse(error: "Email o password sbagliati");
}
