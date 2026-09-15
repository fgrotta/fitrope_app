import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Ritardo prima di `revokeObjectURL`.
///
/// Mai revocare subito dopo `click()`: il browser risolve l'object URL in modo
/// asincrono e su Safari/Firefox il download finisce a volte in "Fallito".
const Duration _kRevokeDelay = Duration(seconds: 60);

/// Fa scaricare [content] come file [fileName].
///
/// **Deve restare sincrona e va chiamata senza `await` interposti tra il click
/// dell'utente e qui**: Safari e Firefox smettono di considerare il download
/// user-initiated e lo bloccano in silenzio.
void downloadTextFile({
  required String content,
  required String fileName,
  String mimeType = 'text/csv',
}) {
  // utf8.encode + Blob binario invece di passare la String: così il BOM finisce
  // nel file come EF BB BF e non viene reinterpretato.
  final bytes = Uint8List.fromList(utf8.encode(content));
  final blob = Blob(
    [bytes.toJS].toJS,
    BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = URL.createObjectURL(blob);
  final anchor = document.createElement('a') as HTMLAnchorElement
    ..href = url
    ..download = fileName;
  // Firefox richiede che l'elemento sia nel documento perché click() scarichi.
  document.body?.appendChild(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
  }
  Future.delayed(_kRevokeDelay, () => URL.revokeObjectURL(url));
}
