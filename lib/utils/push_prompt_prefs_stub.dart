/// Implementazione non-web: nessuno snooze da ricordare.
///
/// A differenza di `download_file_stub.dart` qui il no-op è corretto: sull'app
/// nativa il banner "aggiungi a Home" non esiste e la richiesta di permesso la
/// gestisce il sistema operativo, quindi non c'è niente da rimandare.
bool isPushPromptSnoozed(String key) => false;

void snoozePushPrompt(String key, Duration duration) {}
