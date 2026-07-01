/// Utenti di test che ESISTONO GIÀ in produzione.
///
/// I test E2E girano contro l'ambiente di produzione (nessun emulatore), quindi
/// questi devono essere account reali, dedicati ai test, con email verificata e
/// account attivo.
///
/// Le credenziali NON sono committate: stanno in `integration_test/test_env.json`
/// (gitignored, vedi `test_env.example.json`) e vengono iniettate a runtime con:
///
///   flutter test integration_test -d chrome \
///     --dart-define-from-file=integration_test/test_env.json
///
/// In questo modo non devi più passare le password ad ogni esecuzione.
class TestUser {
  final String email;
  final String password;
  final String role; // 'User' | 'Trainer' | 'Admin'
  final String name; // nome visualizzato (utile per i corsi assegnati al trainer)

  const TestUser({
    required this.email,
    required this.password,
    required this.role,
    this.name = '',
  });
}

// ---------------------------------------------------------------------------
// Valori letti da --dart-define-from-file (test_env.json)
// ---------------------------------------------------------------------------

// Utente normale #1
const String _user1Email = String.fromEnvironment('TEST_USER1_EMAIL');
const String _user1Password = String.fromEnvironment('TEST_USER1_PASSWORD');

// Utente normale #2
const String _user2Email = String.fromEnvironment('TEST_USER2_EMAIL');
const String _user2Password = String.fromEnvironment('TEST_USER2_PASSWORD');

// Trainer
const String _trainerEmail = String.fromEnvironment('TEST_TRAINER_EMAIL');
const String _trainerPassword = String.fromEnvironment('TEST_TRAINER_PASSWORD');
const String _trainerName =
    String.fromEnvironment('TEST_TRAINER_NAME', defaultValue: 'Francesco Trainer');

// Admin
const String _adminEmail = String.fromEnvironment('TEST_ADMIN_EMAIL');
const String _adminPassword = String.fromEnvironment('TEST_ADMIN_PASSWORD');

// ---------------------------------------------------------------------------
// Utenti di test
// ---------------------------------------------------------------------------

const TestUser utenteBase1 = TestUser(
  email: _user1Email,
  password: _user1Password,
  role: 'User',
);

const TestUser utenteBase2 = TestUser(
  email: _user2Email,
  password: _user2Password,
  role: 'User',
);

const TestUser trainerTest = TestUser(
  email: _trainerEmail,
  password: _trainerPassword,
  role: 'Trainer',
  name: _trainerName,
);

const TestUser adminTest = TestUser(
  email: _adminEmail,
  password: _adminPassword,
  role: 'Admin',
);

/// Tutti gli utenti di test, comodo per validazioni o cicli.
const List<TestUser> allTestUsers = [
  utenteBase1,
  utenteBase2,
  trainerTest,
  adminTest,
];

/// Verifica che le credenziali di [user] siano state fornite via env file.
/// Da chiamare in setUpAll dei test che fanno login.
void assertCredentials(TestUser user) {
  if (user.email.isEmpty || user.password.isEmpty) {
    throw StateError(
      'Credenziali mancanti per un utente di ruolo "${user.role}". '
      'Compila integration_test/test_env.json e lancia i test con '
      '--dart-define-from-file=integration_test/test_env.json',
    );
  }
}
