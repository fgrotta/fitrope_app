/// Primitive CSV lato client.
///
/// **Mirror fedele di `functions/src/migration/csv.ts`**, il dialetto già in uso
/// nei report di migrazione: separatore `;`, terminatore `\r\n`, BOM UTF-8 in
/// testa, quoting RFC 4180 con `"` raddoppiate, liste serializzate in JSON. Così
/// l'export della dashboard e quello dei report si aprono uguali nello stesso
/// foglio di calcolo.
///
/// Le ragioni delle scelte valgono identiche qui:
/// - `;` perché Excel con locale italiano usa il `;` come list separator (con la
///   virgola l'utente si ritrova una colonna sola);
/// - BOM perché senza, Excel legge il file come CP1252 e `Niccolò` diventa
///   `NiccolÃ²`.
///
/// **Unica divergenza voluta dal mirror**: la neutralizzazione delle formule
/// (vedi [csvCell]). Il lato server scrive su disco per un admin; questo file
/// finisce in mano a chiunque apra il download, quindi vale la mitigazione
/// standard della CSV injection.
library;

import 'dart:convert';

/// Separatore di campo. Vedi nota sul locale italiano in testa al file.
const String kCsvDelimiter = ';';

/// Terminatore di riga (CRLF, RFC 4180).
const String kCsvLineTerminator = '\r\n';

/// BOM UTF-8. Senza, Excel interpreta il file come CP1252.
const String kCsvBom = '\u{FEFF}';

/// Caratteri che, in testa a un campo, fanno interpretare il contenuto come
/// **formula** da Excel e LibreOffice.
///
/// Non è un caso di scuola: i numeri di telefono iniziano con `+`.
const String _kFormulaTriggers = '=+-@';

/// Serializza un singolo valore in una cella CSV.
///
/// `null` diventa stringa vuota (mai la stringa `"null"`); liste e mappe passano
/// da `jsonEncode`, come fa il mirror server; un campo che inizia con `= + - @`
/// viene preceduto da un apice per restare testo.
String csvCell(Object? value) {
  String text;
  if (value == null) {
    text = '';
  } else if (value is List || value is Map) {
    text = jsonEncode(value);
  } else {
    text = value.toString();
  }

  if (text.isNotEmpty && _kFormulaTriggers.contains(text[0])) {
    text = "'$text";
  }

  final needsQuoting = text.contains(kCsvDelimiter) ||
      text.contains('"') ||
      text.contains('\r') ||
      text.contains('\n');
  if (!needsQuoting) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// Compone un documento CSV completo da [columns] (intestazione) e [rows].
///
/// Ogni riga legge i valori per chiave, quindi una chiave mancante dà una cella
/// vuota invece di disallineare le colonne. [withBom] esiste solo per i test:
/// in produzione il BOM serve sempre.
String csvContent(
  List<String> columns,
  List<Map<String, Object?>> rows, {
  bool withBom = true,
}) {
  final lines = <String>[columns.map(csvCell).join(kCsvDelimiter)];
  for (final row in rows) {
    lines.add(columns.map((c) => csvCell(row[c])).join(kCsvDelimiter));
  }
  return '${withBom ? kCsvBom : ''}'
      '${lines.join(kCsvLineTerminator)}$kCsvLineTerminator';
}
