import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/foundation.dart';

/// Errore di una callable enrollment, con messaggio leggibile per l'utente.
/// `toString()` ritorna SOLO il messaggio (niente prefisso "Exception:"), così
/// i call site che mostrano `$e` in snackbar restano puliti. [code] conserva il
/// codice della Cloud Function (es. `failed-precondition`) per gestioni mirate.
class EnrollmentException implements Exception {
  final String message;
  final String? code;

  const EnrollmentException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Invoca una Cloud Function del dominio iscrizioni (region `europe-west8`)
/// gestendo il boilerplate comune dei wrapper in `lib/api/courses/`:
/// loading nello store, invalidazione cache corsi/utenti, refresh dell'utente
/// corrente (se è il soggetto dell'operazione) e conversione di
/// [FirebaseFunctionsException] in [EnrollmentException].
Future<void> callEnrollmentFunction(
  String functionName,
  Map<String, dynamic> payload, {
  required String userId,
  required String fallbackError,
}) async {
  store.dispatch(StartLoadingAction());
  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable(functionName);
    await callable.call(payload);

    invalidateUsersCache();
    invalidateCoursesCache();
    if (store.state.user?.uid == userId) {
      final userData = await getUserData(userId);
      if (userData != null) {
        store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
      }
    }
  } on FirebaseFunctionsException catch (e) {
    debugPrint('$functionName failed: ${e.code} ${e.message}');
    throw EnrollmentException(e.message ?? fallbackError, code: e.code);
  } catch (error) {
    debugPrint('$functionName failed: $error');
    rethrow;
  } finally {
    store.dispatch(FinishLoadingAction());
  }
}
