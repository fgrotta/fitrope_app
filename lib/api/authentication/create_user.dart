import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/email_validation.dart';

class CreateUserResponse {
  final FitropeUser? user;
  final String? error;
  const CreateUserResponse({this.user, this.error});
}

/// Provisioning Admin-only atomico: il profilo User e il piano iniziale sono
/// creati dalla stessa transazione server-side.
Future<CreateUserResponse> createUser({
  String? email,
  required String name,
  required String lastName,
  required String role,
  required String? planKey,
  bool isAnonymous = false,
  String? numeroTelefono,
}) async {
  SimulationSession.assertNotSimulating('createManagedUser');
  try {
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west8')
        .httpsCallable('createManagedUser')
        .call(<String, dynamic>{
      'email': email == null ? null : EmailValidation.normalize(email),
      'name': name,
      'lastName': lastName,
      'role': role,
      'planKey': planKey,
      'isAnonymous': isAnonymous,
      'numeroTelefono': numeroTelefono,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final uid = data['userId'] as String?;
    if (uid == null || uid.isEmpty) {
      return const CreateUserResponse(error: 'Risposta server non valida');
    }
    invalidateUsersCache();
    // Il server ha creato una shape V2 completa; basta costruire la risposta
    // locale senza una seconda write/client fallback.
    return CreateUserResponse(
      user: FitropeUser(
        uid: uid,
        email: email == null ? '' : EmailValidation.normalize(email),
        name: name,
        lastName: lastName,
        role: role,
        courses: const [],
        isAnonymous: isAnonymous,
        createdAt: DateTime.now(),
        subscriptionModelVersion: 2,
      ),
    );
  } on FirebaseFunctionsException catch (error) {
    return CreateUserResponse(
      error: error.message ?? 'Errore durante la creazione dell\'utente',
    );
  } catch (_) {
    return const CreateUserResponse(
      error: 'Errore durante la creazione dell\'utente',
    );
  }
}
