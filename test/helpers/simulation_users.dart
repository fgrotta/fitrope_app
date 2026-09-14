import 'package:fitrope_app/types/fitrope_user.dart';

/// Utente minimale per i test della modalità simulazione: interessano solo
/// `uid` e `role`, il resto è riempitivo stabile.
FitropeUser simUser({
  required String uid,
  required String role,
  String name = 'Mario',
  String lastName = 'Rossi',
  String email = 'mario.rossi@example.com',
}) =>
    FitropeUser(
      uid: uid,
      role: role,
      name: name,
      lastName: lastName,
      email: email,
      courses: const [],
      createdAt: DateTime(2026, 1, 1),
    );
