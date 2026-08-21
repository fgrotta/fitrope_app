/// Utenti sintetici presenti nell'Emulator Suite o nello staging isolato.
///
/// Il runner fail-closed vieta l'ambiente di produzione.
///
/// Le credenziali NON sono committate: stanno in `integration_test/test_env.json`
/// (gitignored, vedi `test_env.example.json`) e vengono iniettate a runtime con:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/<scenario>.dart -d chrome \
///     --dart-define-from-file=integration_test/test_env.json
///
/// In questo modo non devi più passare le password ad ogni esecuzione.
class TestUser {
  final String email;
  final String password;
  final String role; // 'User' | 'Trainer' | 'Admin'
  final String
      name; // nome visualizzato (utile per i corsi assegnati al trainer)

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
const String _trainerName = String.fromEnvironment('TEST_TRAINER_NAME',
    defaultValue: 'Francesco Trainer');

// Admin
const String _adminEmail = String.fromEnvironment('TEST_ADMIN_EMAIL');
const String _adminPassword = String.fromEnvironment('TEST_ADMIN_PASSWORD');
const String _disabledEmail = String.fromEnvironment('TEST_DISABLED_EMAIL');
const String _disabledPassword =
    String.fromEnvironment('TEST_DISABLED_PASSWORD');
const String _matrixNamespace = String.fromEnvironment('TEST_RUN_NAMESPACE');
const String _matrixPassword = 'test1234';

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

const TestUser disabledTest = TestUser(
  email: _disabledEmail,
  password: _disabledPassword,
  role: 'User',
);

/// Tutti gli utenti di test, comodo per validazioni o cicli.
const List<TestUser> allTestUsers = [
  utenteBase1,
  utenteBase2,
  trainerTest,
  adminTest,
  disabledTest,
];

/// Fixture temporanea creata da `e2eAdmin.js prepare-enrollment-matrix`.
/// UID, email e course id dipendono dal namespace della run, così un retry o
/// una run concorrente non possono leggere dati di un'altra esecuzione.
String _matrixSlug() {
  final slug = _matrixNamespace
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  if (slug.isEmpty) {
    throw StateError(
      'TEST_RUN_NAMESPACE è obbligatorio per gli E2E della matrice enrollment.',
    );
  }
  return slug.length > 48 ? slug.substring(0, 48) : slug;
}

TestUser matrixTestUser(String key) => TestUser(
      email: 'e2e.matrix+${_matrixSlug()}.$key@example.com',
      password: _matrixPassword,
      role: 'User',
    );

String matrixCourseId(String key) => 'e2e_matrix_${_matrixSlug()}_course_$key';

/// Verifica che le credenziali di [user] siano state fornite via env file.
/// Da chiamare in setUpAll dei test che fanno login.
void assertCredentials(TestUser user) {
  if (user.email.isEmpty || user.password.isEmpty) {
    throw StateError(
      'Credenziali mancanti per un utente di ruolo "${user.role}". '
      'Configura il file credenziali del target e lancia i test con '
      '--dart-define-from-file=integration_test/test_env.json',
    );
  }
}
