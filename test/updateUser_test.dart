import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/updateUser.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

/// Test della logica DIFF-BASED di updateUser (buildUserUpdateDiff): è il codice
/// che, sbagliato, romperebbe il salvataggio profilo sotto le firestore.rules
/// field-level (era il BLOCKER del 1° gate PR6). Verifica che il payload
/// contenga SOLO i campi davvero cambiati — niente chiavi aggiunte né Timestamp
/// rinormalizzati spuri.
void main() {
  // Utente "registration-shaped" realistico: fineIscrizione con orario NON
  // 23:59 (come la scriveva registration.dart prima del fix shape).
  FitropeUser original({
    String name = 'Mario',
    List<String> tags = const ['Open'],
    int? entrate = 5,
    DateTime? fine,
    DateTime? certificato,
  }) {
    return FitropeUser(
      uid: 'u1',
      email: 'u1@test.it',
      name: name,
      lastName: 'Rossi',
      role: 'User',
      courses: const [],
      tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
      entrateDisponibili: entrate,
      entrateSettimanali: 0,
      fineIscrizione:
          fine != null ? Timestamp.fromDate(fine) : Timestamp.fromDate(DateTime(2026, 7, 1, 11, 30)),
      isActive: true,
      isAnonymous: false,
      certificatoScadenza: certificato != null ? Timestamp.fromDate(certificato) : null,
      numeroTelefono: '3331112222',
      tipologiaCorsoTags: tags,
      createdAt: DateTime(2026, 1, 1),
      emailNotificationsEnabled: true,
      pushNotificationsEnabled: true,
    );
  }

  /// Replica la chiamata che UserDetailPage fa per un salvataggio "no-op"
  /// (tutti i valori = quelli correnti dell'utente, fineIscrizione ri-passata
  /// come Date dal picker).
  Map<String, dynamic> diffWith(
    FitropeUser u, {
    String? name,
    String? role,
    int? entrateDisponibili,
    int? entrateSettimanali,
    DateTime? fineIscrizione,
    bool? isActive,
    List<String>? tipologiaCorsoTags,
    bool? emailNotificationsEnabled,
    DateTime? certificatoScadenza,
    TipologiaIscrizione? tipologiaIscrizione,
    String? numeroTelefono = '__keep__',
  }) {
    return buildUserUpdateDiff(
      original: u,
      name: name ?? u.name,
      lastName: u.lastName,
      role: role ?? u.role,
      tipologiaIscrizione: tipologiaIscrizione ?? u.tipologiaIscrizione,
      entrateDisponibili: entrateDisponibili ?? u.entrateDisponibili,
      entrateSettimanali: entrateSettimanali ?? u.entrateSettimanali,
      fineIscrizione: fineIscrizione ?? u.fineIscrizione?.toDate(),
      isActive: isActive ?? u.isActive,
      isAnonymous: u.isAnonymous,
      certificatoScadenza: certificatoScadenza ?? u.certificatoScadenza?.toDate(),
      numeroTelefono:
          numeroTelefono == '__keep__' ? u.numeroTelefono : numeroTelefono,
      tipologiaCorsoTags: tipologiaCorsoTags ?? u.tipologiaCorsoTags,
      emailNotificationsEnabled:
          emailNotificationsEnabled ?? u.emailNotificationsEnabled,
      pushNotificationsEnabled: u.pushNotificationsEnabled,
    );
  }

  group('buildUserUpdateDiff — niente diff spuri (il bug del 1° gate)', () {
    test('salvataggio invariato (tutti i valori correnti) → mappa VUOTA', () {
      final u = original();
      expect(diffWith(u), isEmpty);
    });

    test('fineIscrizione stesso GIORNO ma orario diverso → NON emessa', () {
      final u = original(fine: DateTime(2026, 7, 1, 11, 30));
      // La UI la ri-passa come Date dello stesso giorno (picker → y/m/d).
      final diff = diffWith(u, fineIscrizione: DateTime(2026, 7, 1));
      expect(diff.containsKey('fineIscrizione'), isFalse);
    });

    test('tag riordinati → NON emessi (confronto set-based)', () {
      final u = original(tags: ['Open', 'Hyrox']);
      final diff = diffWith(u, tipologiaCorsoTags: ['Hyrox', 'Open']);
      expect(diff.containsKey('tipologiaCorsoTags'), isFalse);
    });

    test('campo numerico svuotato (null) → NON azzera il credito', () {
      final u = original(entrate: 5);
      // int.tryParse('') == null: il vecchio codice avrebbe scritto null.
      final diff = diffWith(u, entrateDisponibili: null);
      expect(diff.containsKey('entrateDisponibili'), isFalse);
    });
  });

  group('buildUserUpdateDiff — emette SOLO i campi cambiati', () {
    test('self cambia solo il nome → {name}', () {
      final u = original();
      expect(diffWith(u, name: 'Luigi'), {'name': 'Luigi'});
    });

    test('self toglie le notifiche email → {emailNotificationsEnabled}', () {
      final u = original();
      expect(diffWith(u, emailNotificationsEnabled: false),
          {'emailNotificationsEnabled': false});
    });

    test('admin cambia ruolo e crediti → {role, entrateDisponibili}', () {
      final u = original(entrate: 5);
      final diff = diffWith(u, role: 'Trainer', entrateDisponibili: 10);
      expect(diff, {'role': 'Trainer', 'entrateDisponibili': 10});
    });

    test('fineIscrizione giorno diverso → emessa normalizzata a 23:59', () {
      final u = original(fine: DateTime(2026, 7, 1, 11, 30));
      final diff = diffWith(u, fineIscrizione: DateTime(2026, 8, 15));
      final ts = diff['fineIscrizione'] as Timestamp;
      final d = ts.toDate();
      expect([d.year, d.month, d.day, d.hour, d.minute], [2026, 8, 15, 23, 59]);
    });

    test('tag realmente cambiati → emessi', () {
      final u = original(tags: ['Open']);
      final diff = diffWith(u, tipologiaCorsoTags: ['Open', 'Hyrox']);
      expect(diff.containsKey('tipologiaCorsoTags'), isTrue);
      expect((diff['tipologiaCorsoTags'] as List).toSet(), {'Open', 'Hyrox'});
    });

    test('numeroTelefono svuotato (null) → emesso come null (azzeramento voluto)', () {
      final u = original();
      final diff = diffWith(u, numeroTelefono: null);
      expect(diff, {'numeroTelefono': null});
    });

    test('data prima ASSENTE poi impostata → emessa a 23:59 (assegnazione scadenza)', () {
      // Utente legacy/manuale senza scadenza: l'admin la imposta per la prima volta.
      final u = FitropeUser(
        uid: 'u1', email: 'u1@test.it', name: 'M', lastName: 'R', role: 'User',
        courses: const [], tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3, fineIscrizione: null, certificatoScadenza: null,
        isActive: true, isAnonymous: false, tipologiaCorsoTags: const ['Open'],
        createdAt: DateTime(2026, 1, 1),
      );
      final fine = buildUserUpdateDiff(
        original: u, name: u.name, lastName: u.lastName, role: u.role,
        tipologiaIscrizione: u.tipologiaIscrizione, entrateSettimanali: u.entrateSettimanali,
        fineIscrizione: DateTime(2026, 8, 15), certificatoScadenza: null,
        isActive: u.isActive, isAnonymous: u.isAnonymous,
        tipologiaCorsoTags: u.tipologiaCorsoTags,
        emailNotificationsEnabled: u.emailNotificationsEnabled,
        pushNotificationsEnabled: u.pushNotificationsEnabled,
      );
      expect((fine['fineIscrizione'] as Timestamp).toDate(), DateTime(2026, 8, 15, 23, 59));

      final cert = buildUserUpdateDiff(
        original: u, name: u.name, lastName: u.lastName, role: u.role,
        tipologiaIscrizione: u.tipologiaIscrizione, entrateSettimanali: u.entrateSettimanali,
        fineIscrizione: null, certificatoScadenza: DateTime(2026, 9, 1),
        isActive: u.isActive, isAnonymous: u.isAnonymous,
        tipologiaCorsoTags: u.tipologiaCorsoTags,
        emailNotificationsEnabled: u.emailNotificationsEnabled,
        pushNotificationsEnabled: u.pushNotificationsEnabled,
      );
      expect((cert['certificatoScadenza'] as Timestamp).toDate(), DateTime(2026, 9, 1, 23, 59));
    });

    test('campi finora scoperti, cambiati → chiave corretta (lastName/entrateSettimanali/isAnonymous/push)', () {
      final u = original();
      expect(diffWith(u, ).isEmpty, isTrue); // sanity: no-op
      expect(
        buildUserUpdateDiff(
          original: u, name: u.name, lastName: 'Bianchi', role: u.role,
          tipologiaIscrizione: u.tipologiaIscrizione,
          entrateDisponibili: u.entrateDisponibili, entrateSettimanali: 3,
          fineIscrizione: u.fineIscrizione?.toDate(), isActive: u.isActive,
          isAnonymous: true, certificatoScadenza: u.certificatoScadenza?.toDate(),
          numeroTelefono: u.numeroTelefono, tipologiaCorsoTags: u.tipologiaCorsoTags,
          emailNotificationsEnabled: u.emailNotificationsEnabled,
          pushNotificationsEnabled: false,
        ),
        {'lastName': 'Bianchi', 'entrateSettimanali': 3, 'isAnonymous': true, 'pushNotificationsEnabled': false},
      );
    });

    test('certificato stesso giorno → non emesso; giorno nuovo → emesso 23:59', () {
      final u = original(certificato: DateTime(2026, 9, 10, 8, 0));
      expect(diffWith(u, certificatoScadenza: DateTime(2026, 9, 10)).containsKey('certificatoScadenza'), isFalse);
      final diff = diffWith(u, certificatoScadenza: DateTime(2026, 10, 1));
      expect((diff['certificatoScadenza'] as Timestamp).toDate().hour, 23);
    });
  });

  // Azzeramenti VOLUTI dall'admin (dropdown "Nessuna" tipologia, rimozione
  // data): il diff DEVE emettere null per persistere lo svuotamento. Le rules
  // Admin lo consentono (blacklist). Test espliciti per fissare l'intenzione e
  // prevenire regressioni distruttive (i campi governano l'eligibility).
  // NB: questi azzeramenti passano `null` ESPLICITO a buildUserUpdateDiff (non
  // via l'helper diffWith, che col `??` lo rimpiazzerebbe col valore originale).
  Map<String, dynamic> diffClearing(
    FitropeUser u, {
    bool clearTipologia = false,
    bool clearFine = false,
    bool clearCertificato = false,
  }) {
    return buildUserUpdateDiff(
      original: u,
      name: u.name,
      lastName: u.lastName,
      role: u.role,
      tipologiaIscrizione: clearTipologia ? null : u.tipologiaIscrizione,
      entrateDisponibili: u.entrateDisponibili,
      entrateSettimanali: u.entrateSettimanali,
      fineIscrizione: clearFine ? null : u.fineIscrizione?.toDate(),
      isActive: u.isActive,
      isAnonymous: u.isAnonymous,
      certificatoScadenza: clearCertificato ? null : u.certificatoScadenza?.toDate(),
      numeroTelefono: u.numeroTelefono,
      tipologiaCorsoTags: u.tipologiaCorsoTags,
      emailNotificationsEnabled: u.emailNotificationsEnabled,
      pushNotificationsEnabled: u.pushNotificationsEnabled,
    );
  }

  group('buildUserUpdateDiff — azzeramenti gestionali (admin) sono VOLUTI', () {
    test('tipologiaIscrizione → null (dropdown "Nessuna") → emesso null', () {
      final diff = diffClearing(original(), clearTipologia: true);
      expect(diff.containsKey('tipologiaIscrizione'), isTrue);
      expect(diff['tipologiaIscrizione'], isNull);
    });

    test('fineIscrizione → null (data rimossa) → emesso null', () {
      final diff =
          diffClearing(original(fine: DateTime(2026, 7, 1, 11, 30)), clearFine: true);
      expect(diff.containsKey('fineIscrizione'), isTrue);
      expect(diff['fineIscrizione'], isNull);
    });

    test('certificatoScadenza → null (rimosso) → emesso null', () {
      final diff = diffClearing(
          original(certificato: DateTime(2026, 9, 10, 8, 0)), clearCertificato: true);
      expect(diff.containsKey('certificatoScadenza'), isTrue);
      expect(diff['certificatoScadenza'], isNull);
    });

    test('campi già null e ripassati null → NESSUN diff (non si scrive null spurio)', () {
      // Utente SENZA fineIscrizione/certificato (costruito inline: l'helper
      // `original` mette un default quando il param è null).
      final u = FitropeUser(
        uid: 'u1',
        email: 'u1@test.it',
        name: 'Mario',
        lastName: 'Rossi',
        role: 'User',
        courses: const [],
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 5,
        entrateSettimanali: 0,
        fineIscrizione: null,
        isActive: true,
        isAnonymous: false,
        certificatoScadenza: null,
        numeroTelefono: '3331112222',
        tipologiaCorsoTags: const ['Open'],
        createdAt: DateTime(2026, 1, 1),
      );
      // fine/certificato originali null, ripassati null → nessuna chiave.
      final diff = buildUserUpdateDiff(
        original: u,
        name: u.name,
        lastName: u.lastName,
        role: u.role,
        tipologiaIscrizione: u.tipologiaIscrizione,
        entrateDisponibili: u.entrateDisponibili,
        entrateSettimanali: u.entrateSettimanali,
        fineIscrizione: null,
        isActive: u.isActive,
        isAnonymous: u.isAnonymous,
        certificatoScadenza: null,
        numeroTelefono: u.numeroTelefono,
        tipologiaCorsoTags: u.tipologiaCorsoTags,
        emailNotificationsEnabled: u.emailNotificationsEnabled,
        pushNotificationsEnabled: u.pushNotificationsEnabled,
      );
      expect(diff.containsKey('fineIscrizione'), isFalse);
      expect(diff.containsKey('certificatoScadenza'), isFalse);
    });
  });
}
