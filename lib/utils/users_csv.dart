/// Costruzione del CSV degli utenti mostrati in `UserListDrawer`. Pura e
/// testabile: tutto l'I/O sta in `download_file.dart`.
///
/// I nomi di colonna riprendono quelli di `userReport()` in
/// `scripts/backfillCourseModel.js` dove il dato è lo stesso, così i due export
/// restano confrontabili.
///
/// Le colonne V1 restano valorizzate solo per utenti V1; per i profili V2 la
/// proiezione autorevole sono le colonne `abbonamenti_attivo_*` /
/// `scadenze_abbonamenti_*`, una coppia per famiglia (OPEN, PT).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/csv.dart';
import 'package:fitrope_app/utils/get_tipologia_iscrizione_label.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';
import 'package:intl/intl.dart';

final DateFormat _csvDateFormat = DateFormat('dd/MM/yyyy');
final DateFormat _csvFileNameStamp = DateFormat('yyyyMMdd-HHmm');

/// Intestazioni, nell'ordine in cui compaiono nel file.
const List<String> kUsersCsvColumns = [
  'nome',
  'cognome',
  'email',
  'numero_telefono',
  'role',
  'is_active',
  'created_at',
  'tipologia_corso_tags',
  'tipologia_iscrizione',
  'entrate_disponibili',
  'entrate_settimanali',
  'fine_iscrizione',
  'abbonamenti_attivo_open',
  'abbonamenti_attivo_pt',
  'scadenze_abbonamenti_open',
  'scadenze_abbonamenti_pt',
  'scadenza_certificato',
  'regolamento_accettato_il',
  'notifiche_email',
  'notifiche_push',
];

String _date(DateTime? value) =>
    value == null ? '' : _csvDateFormat.format(value);

String _timestamp(Timestamp? value) => _date(value?.toDate());

String _bool(bool value) => value ? 'Sì' : 'No';

/// Serializza gli abbonamenti (snapshot multi-abbonamento) come lista di
/// etichette separate da `|`: il separatore di campo è `;`, quindi una lista
/// dentro una cella non può usarlo senza costringere al quoting ogni riga.
String _join(Iterable<String> values) => values.join(' | ');

/// CSV degli utenti passati, **nell'ordine in cui arrivano**: è l'ordine che
/// l'admin vede nel drawer, e l'export deve corrispondere a ciò che si vede.
String buildUsersCsv(List<FitropeUser> users, {bool withBom = true}) {
  final rows = users.map<Map<String, Object?>>((u) {
    final open =
        u.activeSubscriptions.where((s) => s.family == SubscriptionFamily.OPEN);
    final pt =
        u.activeSubscriptions.where((s) => s.family == SubscriptionFamily.PT);
    return {
      'nome': u.name,
      'cognome': u.lastName,
      'email': u.email,
      'numero_telefono': u.numeroTelefono ?? '',
      'role': u.role,
      'is_active': _bool(u.isActive),
      'created_at': _date(u.createdAt),
      // Lista: il mirror server la serializzerebbe in JSON, ma qui la colonna è
      // destinata a un occhio umano in un foglio di calcolo.
      'tipologia_corso_tags': _join(u.tipologiaCorsoTags),
      'tipologia_iscrizione':
          u.subscriptionModelVersion >= 2 || u.tipologiaIscrizione == null
              ? ''
              : getTipologiaIscrizioneLabel(u.tipologiaIscrizione),
      'entrate_disponibili': u.subscriptionModelVersion >= 2
          ? ''
          : u.entrateDisponibili?.toString() ?? '',
      'entrate_settimanali': u.subscriptionModelVersion >= 2
          ? ''
          : u.entrateSettimanali?.toString() ?? '',
      'fine_iscrizione':
          u.subscriptionModelVersion >= 2 ? '' : _timestamp(u.fineIscrizione),
      // Una coppia di colonne per famiglia; più abbonamenti della stessa
      // famiglia restano nella stessa cella, separati da `|`.
      'abbonamenti_attivo_open': _join(open.map(getSubscriptionTitle)),
      'abbonamenti_attivo_pt': _join(pt.map(getSubscriptionTitle)),
      'scadenze_abbonamenti_open':
          _join(open.map((s) => _timestamp(s.endDate))),
      'scadenze_abbonamenti_pt': _join(pt.map((s) => _timestamp(s.endDate))),
      'scadenza_certificato': _timestamp(u.certificatoScadenza),
      'regolamento_accettato_il': _timestamp(u.regolamentoAccettatoIl),
      'notifiche_email': _bool(u.emailNotificationsEnabled),
      'notifiche_push': _bool(u.pushNotificationsEnabled),
    };
  }).toList();

  return csvContent(kUsersCsvColumns, rows, withBom: withBom);
}

/// Nome file: `utenti-<slug del titolo>-<yyyyMMdd-HHmm>.csv`.
///
/// Lo slug tiene solo `[a-z0-9-]` (accenti normalizzati): alcuni browser
/// troncano il nome al primo carattere che non gradiscono.
String usersCsvFileName(String listTitle, DateTime now) {
  final slug = _slugify(listTitle);
  final stamp = _csvFileNameStamp.format(now);
  return slug.isEmpty ? 'utenti-$stamp.csv' : 'utenti-$slug-$stamp.csv';
}

const Map<String, String> _accentFolding = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String _slugify(String value) {
  final folded = value.toLowerCase().split('').map((c) {
    return _accentFolding[c] ?? c;
  }).join();
  return folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
