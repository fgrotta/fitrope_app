// ignore_for_file: avoid_print
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitrope_app/api/get_user_data.dart';
import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/services/notification_service.dart';
import 'package:fitrope_app/api/subscriptions/signup_trial.dart';

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
  // PRIMA di StartLoadingAction, o il Loader resterebbe acceso per sempre.
  SimulationSession.assertNotSimulating('signInWithEmailPassword');
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

      if (userData != null) {
        var fitropeUser = FitropeUser.fromJson(userData);

        // Controlla se l'utente è attivo
        if (!fitropeUser.isActive) {
          // Disconnetti l'utente da Firebase Auth
          await FirebaseAuth.instance.signOut();
          store.dispatch(FinishLoadingAction());
          return SignInResponse(
              error:
                  "Il tuo account è stato disattivato. Contatta l'amministratore per maggiori informazioni.");
        }

        // Best effort, e solo per chi ha il marker create-only della
        // self-registration: per i profili esistenti il server farebbe un
        // no-op dopo un round-trip alla callable.
        if (needsSignupTrialGrant(userData)) {
          try {
            await grantSignupTrial();
            final refreshed = await getUserData(uid);
            if (refreshed != null) {
              fitropeUser = FitropeUser.fromJson(refreshed);
            }
          } catch (error) {
            print('Retry prova signup fallito: $error');
          }
        }

        // Il Loader copre l'intera attesa: spento solo dopo l'ultimo await.
        store.dispatch(FinishLoadingAction());

        // Solo lo staff usa la lista completa degli utenti: per un socio sarebbe
        // l'intera collection `users` scaricata per niente. Popolata in
        // background, non blocca il login.
        if (fitropeUser.role == 'Admin' || fitropeUser.role == 'Trainer') {
          unawaited(getUsers().catchError((error) {
            print('Background cache population failed: $error');
            return <FitropeUser>[];
          }));
        }

        // L'identità del client SDK OneSignal (login/email/preferenza push) la
        // lega `Protected._syncOneSignalIdentity` al mount, che copre anche il
        // reload. Qui resta solo la garanzia server-side: l'utente esiste su
        // OneSignal con la sua email, indipendentemente dal permesso push del
        // browser. Fire-and-forget.
        if (fitropeUser.email.isNotEmpty) {
          unawaited(ensureOneSignalUser(fitropeUser.uid, fitropeUser.email));
        }

        return SignInResponse(user: fitropeUser, error: "");
      }

      store.dispatch(FinishLoadingAction());
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
