import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/users_csv.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser _user({
  String name = 'Mario',
  String lastName = 'Rossi',
  String email = 'mario@example.com',
  String? numeroTelefono,
  String role = 'User',
  bool isActive = true,
  DateTime? createdAt,
  List<String> tipologiaCorsoTags = const ['Open'],
  TipologiaIscrizione? tipologiaIscrizione,
  int? entrateDisponibili,
  int? entrateSettimanali,
  Timestamp? fineIscrizione,
  Timestamp? certificatoScadenza,
  Timestamp? regolamentoAccettatoIl,
  bool emailNotificationsEnabled = true,
  bool pushNotificationsEnabled = true,
  List<UserSubscription> activeSubscriptions = const [],
}) {
  return FitropeUser(
    uid: 'uid-$email',
    email: email,
    name: name,
    lastName: lastName,
    courses: const [],
    role: role,
    isActive: isActive,
    createdAt: createdAt ?? DateTime(2024, 3, 7),
    numeroTelefono: numeroTelefono,
    tipologiaCorsoTags: tipologiaCorsoTags,
    tipologiaIscrizione: tipologiaIscrizione,
    entrateDisponibili: entrateDisponibili,
    entrateSettimanali: entrateSettimanali,
    fineIscrizione: fineIscrizione,
    certificatoScadenza: certificatoScadenza,
    regolamentoAccettatoIl: regolamentoAccettatoIl,
    emailNotificationsEnabled: emailNotificationsEnabled,
    pushNotificationsEnabled: pushNotificationsEnabled,
    activeSubscriptions: activeSubscriptions,
  );
}

/// Righe dati (header escluso) di un CSV generato senza BOM.
List<String> _dataRows(String csv) =>
    csv.split('\r\n').where((l) => l.isNotEmpty).skip(1).toList();

/// Celle di una riga semplice (nessun campo quotato).
List<String> _cells(String row) => row.split(';');

void main() {
  group('buildUsersCsv', () {
    test('lista vuota → solo header', () {
      final csv = buildUsersCsv(const [], withBom: false);

      expect(csv, '${kUsersCsvColumns.join(';')}\r\n');
    });

    test('header nell\'ordine dichiarato, con BOM di default', () {
      final csv = buildUsersCsv([_user()]);

      expect(
          csv.startsWith('\u{FEFF}${kUsersCsvColumns.join(';')}\r\n'), isTrue);
    });

    test('una riga per utente, nell\'ordine di input (nessun sort)', () {
      final csv = buildUsersCsv(
        [
          _user(name: 'Zoe', email: 'zoe@example.com'),
          _user(name: 'Aldo', email: 'aldo@example.com'),
        ],
        withBom: false,
      );

      final rows = _dataRows(csv);
      expect(rows.length, 2);
      expect(_cells(rows[0]).first, 'Zoe');
      expect(_cells(rows[1]).first, 'Aldo');
    });

    test('i null diventano stringa vuota, non "null"', () {
      final csv = buildUsersCsv([_user()], withBom: false);

      expect(csv, isNot(contains('null')));
      final cells = _cells(_dataRows(csv).single);
      expect(cells[kUsersCsvColumns.indexOf('numero_telefono')], '');
      expect(cells[kUsersCsvColumns.indexOf('tipologia_iscrizione')], '');
      expect(cells[kUsersCsvColumns.indexOf('fine_iscrizione')], '');
      expect(cells[kUsersCsvColumns.indexOf('entrate_disponibili')], '');
      expect(cells[kUsersCsvColumns.indexOf('scadenza_certificato')], '');
      for (final column in const [
        'abbonamenti_attivo_open',
        'abbonamenti_attivo_pt',
        'scadenze_abbonamenti_open',
        'scadenze_abbonamenti_pt',
      ]) {
        expect(cells[kUsersCsvColumns.indexOf(column)], '', reason: column);
      }
    });

    test('il telefono con prefisso + non diventa una formula', () {
      final csv = buildUsersCsv(
        [_user(numeroTelefono: '+393331112222')],
        withBom: false,
      );

      final cells = _cells(_dataRows(csv).single);
      expect(
          cells[kUsersCsvColumns.indexOf('numero_telefono')], "'+393331112222");
    });

    test('date in dd/MM/yyyy', () {
      final csv = buildUsersCsv(
        [
          _user(
            createdAt: DateTime(2024, 1, 5),
            fineIscrizione: Timestamp.fromDate(DateTime(2025, 12, 31)),
            certificatoScadenza: Timestamp.fromDate(DateTime(2026, 2, 28)),
            regolamentoAccettatoIl: Timestamp.fromDate(DateTime(2024, 1, 6)),
          )
        ],
        withBom: false,
      );

      final cells = _cells(_dataRows(csv).single);
      expect(cells[kUsersCsvColumns.indexOf('created_at')], '05/01/2024');
      expect(cells[kUsersCsvColumns.indexOf('fine_iscrizione')], '31/12/2025');
      expect(cells[kUsersCsvColumns.indexOf('scadenza_certificato')],
          '28/02/2026');
      expect(cells[kUsersCsvColumns.indexOf('regolamento_accettato_il')],
          '06/01/2024');
    });

    test('booleani in italiano', () {
      final csv = buildUsersCsv(
        [
          _user(
            isActive: false,
            emailNotificationsEnabled: false,
            pushNotificationsEnabled: true,
          )
        ],
        withBom: false,
      );

      final cells = _cells(_dataRows(csv).single);
      expect(cells[kUsersCsvColumns.indexOf('is_active')], 'No');
      expect(cells[kUsersCsvColumns.indexOf('notifiche_email')], 'No');
      expect(cells[kUsersCsvColumns.indexOf('notifiche_push')], 'Sì');
    });

    test('riusa le label della UI per la tipologia legacy', () {
      final csv = buildUsersCsv(
        [
          _user(
            tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
            entrateDisponibili: 7,
            entrateSettimanali: 3,
          )
        ],
        withBom: false,
      );

      final cells = _cells(_dataRows(csv).single);
      expect(cells[kUsersCsvColumns.indexOf('tipologia_iscrizione')],
          'Pacchetto Entrate');
      expect(cells[kUsersCsvColumns.indexOf('entrate_disponibili')], '7');
      expect(cells[kUsersCsvColumns.indexOf('entrate_settimanali')], '3');
    });

    test('tag multipli in una cella, abbonamenti divisi per famiglia', () {
      final csv = buildUsersCsv(
        [
          _user(
            tipologiaCorsoTags: const ['Open', 'Personal Trainer'],
            activeSubscriptions: [
              UserSubscription(
                planKey: 'open_2x_3m',
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.FREQUENCY,
                courseTypeTags: const {'Open'},
                weeklyFrequency: 2,
                startDate: Timestamp.fromDate(DateTime(2025, 1, 1)),
                endDate: Timestamp.fromDate(DateTime(2025, 4, 1)),
              ),
              UserSubscription(
                planKey: 'pt_10i_1m',
                family: SubscriptionFamily.PT,
                billingMode: BillingMode.ENTRIES,
                courseTypeTags: const {'Personal Trainer'},
                remainingEntries: 4,
                startDate: Timestamp.fromDate(DateTime(2025, 1, 1)),
                endDate: Timestamp.fromDate(DateTime(2025, 2, 1)),
              ),
            ],
          )
        ],
        withBom: false,
      );

      final row = _dataRows(csv).single;
      // Il `|` non forza il quoting: le colonne restano allineate.
      expect(row, isNot(contains('"')));
      final cells = _cells(row);
      expect(cells[kUsersCsvColumns.indexOf('tipologia_corso_tags')],
          'Open | Personal Trainer');
      expect(cells[kUsersCsvColumns.indexOf('scadenze_abbonamenti_open')],
          '01/04/2025');
      expect(cells[kUsersCsvColumns.indexOf('scadenze_abbonamenti_pt')],
          '01/02/2025');
      for (final column in const [
        'abbonamenti_attivo_open',
        'abbonamenti_attivo_pt',
      ]) {
        final cell = cells[kUsersCsvColumns.indexOf(column)];
        expect(cell, isNotEmpty, reason: column);
        expect(cell, isNot(contains('|')), reason: column);
      }
    });

    test('più abbonamenti della stessa famiglia restano nella sua cella', () {
      final csv = buildUsersCsv(
        [
          _user(
            activeSubscriptions: [
              UserSubscription(
                planKey: 'open_2x_3m',
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.FREQUENCY,
                courseTypeTags: const {'Open'},
                weeklyFrequency: 2,
                startDate: Timestamp.fromDate(DateTime(2025, 1, 1)),
                endDate: Timestamp.fromDate(DateTime(2025, 4, 1)),
              ),
              UserSubscription(
                planKey: 'open_10i_1m',
                family: SubscriptionFamily.OPEN,
                billingMode: BillingMode.ENTRIES,
                courseTypeTags: const {'Open'},
                remainingEntries: 10,
                startDate: Timestamp.fromDate(DateTime(2025, 1, 1)),
                endDate: Timestamp.fromDate(DateTime(2025, 2, 1)),
              ),
            ],
          )
        ],
        withBom: false,
      );

      final cells = _cells(_dataRows(csv).single);
      expect(cells[kUsersCsvColumns.indexOf('scadenze_abbonamenti_open')],
          '01/04/2025 | 01/02/2025');
      expect(
        cells[kUsersCsvColumns.indexOf('abbonamenti_attivo_open')],
        contains('|'),
      );
      expect(cells[kUsersCsvColumns.indexOf('abbonamenti_attivo_pt')], '');
      expect(cells[kUsersCsvColumns.indexOf('scadenze_abbonamenti_pt')], '');
    });

    test('un campo con ; o accenti resta leggibile e quotato dove serve', () {
      final csv = buildUsersCsv(
        [_user(name: 'Niccolò', lastName: 'De Rossi; jr')],
        withBom: false,
      );

      expect(csv, contains('Niccolò'));
      expect(csv, contains('"De Rossi; jr"'));
    });
  });

  group('usersCsvFileName', () {
    test('slugifica titolo e timestamp', () {
      expect(
        usersCsvFileName('Utenti attivi', DateTime(2026, 9, 15, 14, 7)),
        'utenti-utenti-attivi-20260915-1407.csv',
      );
    });

    test('normalizza accenti e caratteri fuori [a-z0-9-]', () {
      expect(
        usersCsvFileName(
            'Abbonamento Annuale – più di 5€!', DateTime(2026, 1, 2, 3, 4)),
        'utenti-abbonamento-annuale-piu-di-5-20260102-0304.csv',
      );
    });

    test('non lascia trattini in testa o in coda', () {
      final name = usersCsvFileName('— Prova —', DateTime(2026, 1, 2, 3, 4));

      expect(name, 'utenti-prova-20260102-0304.csv');
    });

    test('titolo senza caratteri utili → nome senza slug', () {
      expect(
        usersCsvFileName('///', DateTime(2026, 1, 2, 3, 4)),
        'utenti-20260102-0304.csv',
      );
    });
  });
}
