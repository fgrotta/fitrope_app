/// Implementazione non-web: **lancia**, non è un no-op silenzioso.
///
/// L'unico chiamante è la dashboard admin, che è desktop-web-only: arrivarci da
/// mobile sarebbe una regressione di routing, e deve farsi vedere invece di
/// produrre un bottone che non fa niente.
void downloadTextFile({
  required String content,
  required String fileName,
  String mimeType = 'text/csv',
}) {
  throw UnsupportedError(
    'Il download di file è disponibile solo sulla versione web dell\'app.',
  );
}
