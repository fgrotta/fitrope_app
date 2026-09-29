import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/certificate_alerts.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 9, 22, 12);

UserSubscription _sub(
  String planKey, {
  DateTime? end,
  int? remainingEntries,
}) {
  final plan = SubscriptionPlans.byKey(planKey)!;
  return UserSubscription(
    id: planKey,
    planKey: planKey,
    family: plan.family,
    billingMode: plan.billingMode,
    courseTypeTags: plan.grantedCourseTypeTags,
    weeklyFrequency: plan.weeklyFrequency,
    remainingEntries: remainingEntries ?? plan.entries,
    startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
    endDate: Timestamp.fromDate(end ?? _now.add(const Duration(days: 60))),
  );
}

FitropeUser _user(
  String uid, {
  String? name,
  DateTime? certificato,
  List<UserSubscription>? subscriptions,
  int modelVersion = 2,
  TipologiaIscrizione? tipologia,
  DateTime? fineIscrizione,
  bool isActive = true,
  String role = 'User',
}) {
  return FitropeUser(
    uid: uid,
    email: '$uid@example.com',
    name: name ?? 'Test',
    lastName: uid,
    role: role,
    courses: const [],
    createdAt: _now,
    activeSubscriptions: subscriptions ?? [_sub('open_2x_1m')],
    subscriptionModelVersion: modelVersion,
    tipologiaIscrizione: tipologia,
    fineIscrizione:
        fineIscrizione == null ? null : Timestamp.fromDate(fineIscrizione),
    certificatoScadenza:
        certificato == null ? null : Timestamp.fromDate(certificato),
    isActive: isActive,
  );
}

List<String> _uids(List<FitropeUser> users) => users.map((u) => u.uid).toList();

void main() {
  group('certificatoAlertOf', () {
    test('senza certificato → mancante', () {
      expect(
          certificatoAlertOf(_user('a'), now: _now), CertificatoAlert.mancante);
    });

    test('scaduto ieri → scaduto', () {
      final u = _user('a', certificato: _now.subtract(const Duration(days: 1)));
      expect(certificatoAlertOf(u, now: _now), CertificatoAlert.scaduto);
    });

    test('scaduto da poche ore → scaduto, non "0 giorni rimanenti"', () {
      final u =
          _user('a', certificato: _now.subtract(const Duration(hours: 3)));
      expect(certificatoAlertOf(u, now: _now), CertificatoAlert.scaduto);
    });

    test('entro la soglia → in scadenza, bordo compreso', () {
      final tra5 = _user('a', certificato: _now.add(const Duration(days: 5)));
      final bordo = _user(
        'b',
        certificato: _now.add(
            const Duration(days: CertificatoHelper.GIORNI_SOGLIA_SCADENZA)),
      );
      expect(certificatoAlertOf(tra5, now: _now), CertificatoAlert.inScadenza);
      expect(certificatoAlertOf(bordo, now: _now), CertificatoAlert.inScadenza);
    });

    test('valido oltre la soglia → null', () {
      final u = _user(
        'a',
        certificato: _now.add(const Duration(
            days: CertificatoHelper.GIORNI_SOGLIA_SCADENZA, minutes: 1)),
      );
      expect(certificatoAlertOf(u, now: _now), isNull);
    });
  });

  group('matchesCertificatoFilter', () {
    const tutti = CertificatoListFilter.tutti;
    const combinato = CertificatoListFilter.scadutoOInScadenza;
    const scaduto = CertificatoListFilter.scaduto;
    const inScadenza = CertificatoListFilter.inScadenza;
    const mancante = CertificatoListFilter.mancante;

    List<CertificatoListFilter> passati(FitropeUser u) => [
          for (final f in CertificatoListFilter.values)
            if (matchesCertificatoFilter(u, f, now: _now)) f,
        ];

    test('scaduto da poche ore → Scaduto e combinato, non In scadenza', () {
      final u =
          _user('a', certificato: _now.subtract(const Duration(hours: 3)));
      expect(passati(u), [tutti, combinato, scaduto]);
    });

    test('scade esattamente a +30 giorni → in scadenza, bordo compreso', () {
      final u = _user('a',
          certificato:
              _now.add(const Duration(days: giorniSogliaFiltroCertificato)));
      expect(passati(u), [tutti, combinato, inScadenza]);
    });

    test('scade a +30 giorni e 1 minuto → solo Tutti', () {
      final u = _user('a',
          certificato: _now.add(
              const Duration(days: giorniSogliaFiltroCertificato, minutes: 1)));
      expect(passati(u), [tutti]);
    });

    test('a +20 giorni: in scadenza per il filtro, non per il default', () {
      final u = _user('a', certificato: _now.add(const Duration(days: 20)));
      expect(passati(u), [tutti, combinato, inScadenza]);
      expect(certificatoAlertOf(u, now: _now), isNull);
    });

    test('senza certificato → solo Senza certificato e Tutti', () {
      expect(passati(_user('a')), [tutti, mancante]);
    });

    test('non richiede un abbonamento vivo', () {
      final u = _user('a',
          subscriptions: const [],
          certificato: _now.subtract(const Duration(days: 1)));
      expect(matchesCertificatoFilter(u, scaduto, now: _now), isTrue);
    });
  });

  group('giorniAllaScadenzaCertificato', () {
    test('giorni di calendario, non intervalli di 24 ore', () {
      final stasera = _user('a', certificato: DateTime(2026, 9, 22, 23));
      final domattina = _user('b', certificato: DateTime(2026, 9, 23, 1));
      final ieri = _user('c', certificato: DateTime(2026, 9, 21, 23));
      expect(giorniAllaScadenzaCertificato(stasera, now: _now), 0);
      expect(giorniAllaScadenzaCertificato(domattina, now: _now), 1);
      expect(giorniAllaScadenzaCertificato(ieri, now: _now), -1);
      expect(giorniAllaScadenzaCertificato(_user('d'), now: _now), isNull);
    });
  });

  group('hasNonTrialLiveSubscription', () {
    test('V2 con solo la Prova → falso', () {
      final u = _user('a', subscriptions: [_sub('open_trial_1i_30d')]);
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });

    test('Prova più Open vivo → vero', () {
      final u = _user('a', subscriptions: [
        _sub('open_trial_1i_30d'),
        _sub('open_2x_1m'),
      ]);
      expect(hasNonTrialLiveSubscription(u, now: _now), isTrue);
    });

    test('V2 senza snapshot vivi → falso', () {
      final u = _user('a', subscriptions: [
        _sub('open_2x_1m', end: _now.subtract(const Duration(days: 1))),
      ]);
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });

    test('V2 senza snapshot vivi ignora la fineIscrizione legacy', () {
      final u = _user(
        'a',
        subscriptions: const [],
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        fineIscrizione: _now.add(const Duration(days: 10)),
      );
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });

    test('pacchetto con 0 ingressi non scaduto → vero', () {
      final u = _user('a', subscriptions: [
        _sub('open_10i_3m', remainingEntries: 0),
      ]);
      expect(hasNonTrialLiveSubscription(u, now: _now), isTrue);
    });

    test('V1 ABBONAMENTO_PROVA → falso', () {
      final u = _user(
        'a',
        subscriptions: const [],
        modelVersion: 1,
        tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
        fineIscrizione: _now.add(const Duration(days: 10)),
      );
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });

    test('V1 PACCHETTO_ENTRATE valido → vero', () {
      final u = _user(
        'a',
        subscriptions: const [],
        modelVersion: 1,
        tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
        fineIscrizione: _now.add(const Duration(days: 10)),
      );
      expect(hasNonTrialLiveSubscription(u, now: _now), isTrue);
    });

    test('V1 scaduto → falso', () {
      final u = _user(
        'a',
        subscriptions: const [],
        modelVersion: 1,
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        fineIscrizione: _now.subtract(const Duration(days: 1)),
      );
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });

    test('V1 senza tipologia → falso', () {
      final u = _user(
        'a',
        subscriptions: const [],
        modelVersion: 1,
        fineIscrizione: _now.add(const Duration(days: 10)),
      );
      expect(hasNonTrialLiveSubscription(u, now: _now), isFalse);
    });
  });

  group('usersNeedingCertificateAttention', () {
    test('filtra per stato del socio, abbonamento e certificato', () {
      final mancante = _user('mancante');
      final valido = _user('valido', certificato: DateTime(2027, 9, 22));
      final disattivato = _user('disattivato', isActive: false);
      final prova = _user('prova', subscriptions: [_sub('open_trial_1i_30d')]);
      final senzaAbbonamento = _user('senza', subscriptions: const []);
      final admin = _user('admin', role: 'Admin', subscriptions: const []);
      final trainerConAbbonamento = _user('trainer', role: 'Trainer');

      final result = usersNeedingCertificateAttention([
        mancante,
        valido,
        disattivato,
        prova,
        senzaAbbonamento,
        admin,
        trainerConAbbonamento,
      ], now: _now);

      expect(_uids(result), ['mancante', 'trainer']);
    });

    test(
        'mancanti per nome, scaduti dal più vecchio, in scadenza dal più vicino',
        () {
      final users = [
        _user('scade10', certificato: _now.add(const Duration(days: 10))),
        _user('scadutoIeri',
            certificato: _now.subtract(const Duration(days: 1))),
        _user('mancanteZ', name: 'Zeno'),
        _user('scade2', certificato: _now.add(const Duration(days: 2))),
        _user('scadutoMese',
            certificato: _now.subtract(const Duration(days: 30))),
        _user('mancanteA', name: 'anna'),
      ];

      final result = usersNeedingCertificateAttention(users, now: _now);

      expect(_uids(result), [
        'mancanteA',
        'mancanteZ',
        'scadutoMese',
        'scadutoIeri',
        'scade2',
        'scade10',
      ]);
    });
  });
}
