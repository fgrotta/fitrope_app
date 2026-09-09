/// Su mobile non serve: la persistenza sta nello storage nativo dell'app e non
/// c'è la corsa col ripristino di sessione che si vede sul web.
Future<void> clearFirebaseAuthPersistence({
  required String apiKey,
  required String appName,
}) async {}
