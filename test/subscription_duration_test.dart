import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_duration.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime(2026, 9, 22);

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
  List<UserSubscription> subscriptions = const [],
  int modelVersion = 2,
  TipologiaIscrizione? tipologia,
  int? entrateDisponibili,
}) {
  return FitropeUser(
    uid: uid,
    email: '$uid@example.com',
    name: 'Test',
    lastName: uid,
    role: 'User',
    courses: const [],
    createdAt: _now,
    activeSubscriptions: subscriptions,
    subscriptionModelVersion: modelVersion,
    tipologiaIscrizione: tipologia,
    entrateDisponibili: entrateDisponibili,
  );
}

List<String> _uids(List<FitropeUser> users) => users.map((u) => u.uid).toList();

void main() {
  group('subscriptionDurationOf', () {
    test('mappa i piani alla durata', () {
      expect(subscriptionDurationOf(_sub('open_trial_1i_30d')),
          SubscriptionDuration.prova);
      expect(subscriptionDurationOf(_sub('open_2x_1m')),
          SubscriptionDuration.mensile);
      expect(subscriptionDurationOf(_sub('open_unlim_3m')),
          SubscriptionDuration.trimestrale);
      expect(subscriptionDurationOf(_sub('open_10i_6m')),
          SubscriptionDuration.semestrale);
      expect(subscriptionDurationOf(_sub('pt_10i_12m')),
          SubscriptionDuration.annuale);
    });

    test('ogni piano del catalogo ha una durata', () {
      // Vincola il catalogo: una nuova durata rompe qui invece di sparire in
      // silenzio dalla dashboard.
      for (final plan in SubscriptionPlans.all) {
        expect(subscriptionDurationOf(_sub(plan.key)), isNotNull,
            reason: plan.key);
      }
    });

    test('etichette nell\'ordine di visualizzazione', () {
      expect(SubscriptionDuration.values.map((d) => d.label).toList(), [
        'Abbonamento Prova',
        'Abbonamento mensile',
        'Abbonamento trimestrale',
        'Abbonamento semestrale',
        'Abbonamento annuale',
      ]);
    });
  });

  group('usersBySubscriptionDuration', () {
    test('input vuoto → cinque voci a zero, in ordine', () {
      final result = usersBySubscriptionDuration(const [], now: _now);

      expect(result.map((e) => e.key).toList(), SubscriptionDuration.values);
      expect(result.every((e) => e.value.isEmpty), isTrue);
    });

    test('stessa durata su due famiglie → socio contato una volta', () {
      final u = _user('a', subscriptions: [
        _sub('open_2x_1m'),
        _sub('pt_10i_1m'),
      ]);

      final result = usersBySubscriptionDuration([u], now: _now);

      expect(_uids(result[SubscriptionDuration.mensile.index].value), ['a']);
    });

    test('durate diverse → il socio compare in entrambe le voci', () {
      final u = _user('a', subscriptions: [
        _sub('open_2x_1m'),
        _sub('pt_10i_12m'),
      ]);

      final result = usersBySubscriptionDuration([u], now: _now);

      expect(_uids(result[SubscriptionDuration.mensile.index].value), ['a']);
      expect(_uids(result[SubscriptionDuration.annuale.index].value), ['a']);
      expect(result[SubscriptionDuration.trimestrale.index].value, isEmpty);
    });

    test('abbonamenti scaduti esclusi', () {
      final u = _user('a', subscriptions: [
        _sub('open_2x_3m', end: _now.subtract(const Duration(days: 1))),
      ]);

      final result = usersBySubscriptionDuration([u], now: _now);

      expect(result.every((e) => e.value.isEmpty), isTrue);
    });

    test('utente V1 non contato', () {
      final u = _user(
        'v1',
        modelVersion: 1,
        tipologia: TipologiaIscrizione.ABBONAMENTO_MENSILE,
      );

      final result = usersBySubscriptionDuration([u], now: _now);

      expect(result.every((e) => e.value.isEmpty), isTrue);
    });
  });

  group('usersBySubscriptionFamily', () {
    test('ordine fisso OPEN, PT con voci a zero', () {
      final result = usersBySubscriptionFamily(const [], now: _now);

      expect(result.map((e) => e.key).toList(), [
        SubscriptionFamily.OPEN,
        SubscriptionFamily.PT,
      ]);
      expect(result.every((e) => e.value.isEmpty), isTrue);
    });

    test('due abbonamenti Open → un solo socio in Open', () {
      final u = _user('a', subscriptions: [
        _sub('open_2x_1m'),
        _sub('open_10i_3m'),
      ]);

      final result = usersBySubscriptionFamily([u], now: _now);

      expect(_uids(result[0].value), ['a']);
      expect(result[1].value, isEmpty);
    });

    test('abbonamenti scaduti esclusi', () {
      final u = _user('a', subscriptions: [
        _sub('pt_10i_1m', end: _now.subtract(const Duration(days: 1))),
      ]);

      final result = usersBySubscriptionFamily([u], now: _now);

      expect(result.every((e) => e.value.isEmpty), isTrue);
    });
  });

  group('averageRemainingEntries', () {
    test('lista vuota → nessun utente, media 0.0', () {
      final (users, avg) = averageRemainingEntries(const [], now: _now);

      expect(users, isEmpty);
      expect(avg, 0.0);
    });

    test('media sugli abbonamenti a ingressi vivi', () {
      final a = _user('a', subscriptions: [
        _sub('open_10i_1m', remainingEntries: 4),
        _sub('pt_10i_1m', remainingEntries: 8),
        _sub('open_2x_1m'),
      ]);
      final b = _user('b', subscriptions: [_sub('open_2x_1m')]);

      final (users, avg) = averageRemainingEntries([a, b], now: _now);

      expect(_uids(users), ['a']);
      expect(avg, 6.0);
    });

    test('abbonamento a ingressi scaduto escluso', () {
      final a = _user('a', subscriptions: [
        _sub('open_10i_1m', remainingEntries: 2),
        _sub(
          'open_10i_3m',
          remainingEntries: 10,
          end: _now.subtract(const Duration(days: 1)),
        ),
      ]);
      final b = _user('b', subscriptions: [
        _sub(
          'pt_10i_1m',
          remainingEntries: 10,
          end: _now.subtract(const Duration(days: 1)),
        ),
      ]);

      final (users, avg) = averageRemainingEntries([a, b], now: _now);

      expect(_uids(users), ['a']);
      expect(avg, 2.0);
    });

    test('utente V1 con entrateDisponibili ignorato', () {
      final v1 = _user(
        'v1',
        modelVersion: 1,
        tipologia: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 7,
      );

      final (users, avg) = averageRemainingEntries([v1], now: _now);

      expect(users, isEmpty);
      expect(avg, 0.0);
    });
  });

  group('usersByExpiringSubscriptionDuration', () {
    List<String> row(
      List<MapEntry<SubscriptionDuration, List<FitropeUser>>> r,
      SubscriptionDuration d,
    ) =>
        _uids(r[d.index].value);

    test('input vuoto → cinque voci a zero, in ordine', () {
      final result = usersByExpiringSubscriptionDuration(const [], now: _now);

      expect(result.map((e) => e.key).toList(), SubscriptionDuration.values);
      expect(result.every((e) => e.value.isEmpty), isTrue);
    });

    test('solo gli abbonamenti nella finestra dei 30 giorni', () {
      final dentro = _user(
        'dentro',
        subscriptions: [
          _sub('open_2x_1m', end: _now.add(const Duration(days: 10))),
        ],
      );
      final bordo = _user(
        'bordo',
        subscriptions: [
          _sub('open_2x_3m', end: _now.add(const Duration(days: 30))),
        ],
      );
      final lontano = _user(
        'lontano',
        subscriptions: [
          _sub('open_2x_6m', end: _now.add(const Duration(days: 31))),
        ],
      );
      final scaduto = _user(
        'scaduto',
        subscriptions: [
          _sub('open_2x_12m', end: _now.subtract(const Duration(days: 1))),
        ],
      );

      final result = usersByExpiringSubscriptionDuration([
        dentro,
        bordo,
        lontano,
        scaduto,
      ], now: _now);

      expect(row(result, SubscriptionDuration.mensile), ['dentro']);
      expect(row(result, SubscriptionDuration.trimestrale), ['bordo']);
      expect(row(result, SubscriptionDuration.semestrale), isEmpty);
      expect(row(result, SubscriptionDuration.annuale), isEmpty);
    });

    test('conta la durata dell\'abbonamento che scade, non degli altri', () {
      final u = _user(
        'a',
        subscriptions: [
          _sub('open_2x_1m', end: _now.add(const Duration(days: 5))),
          _sub('pt_10i_12m', end: _now.add(const Duration(days: 200))),
        ],
      );

      final result = usersByExpiringSubscriptionDuration([u], now: _now);

      expect(row(result, SubscriptionDuration.mensile), ['a']);
      expect(row(result, SubscriptionDuration.annuale), isEmpty);
    });

    test('due abbonamenti della stessa durata in scadenza → un socio', () {
      final u = _user(
        'a',
        subscriptions: [
          _sub('open_2x_1m', end: _now.add(const Duration(days: 5))),
          _sub('pt_10i_1m', end: _now.add(const Duration(days: 8))),
        ],
      );

      final result = usersByExpiringSubscriptionDuration([u], now: _now);

      expect(row(result, SubscriptionDuration.mensile), ['a']);
    });

    test('la Prova in scadenza finisce nella sua voce', () {
      final u = _user(
        'p',
        subscriptions: [
          _sub('open_trial_1i_30d', end: _now.add(const Duration(days: 3))),
        ],
      );

      final result = usersByExpiringSubscriptionDuration([u], now: _now);

      expect(row(result, SubscriptionDuration.prova), ['p']);
    });

    test('piano legacy V1 in scadenza non ha durata e non compare', () {
      final v1 = FitropeUser(
        uid: 'v1',
        email: 'v1@example.com',
        name: 'Test',
        lastName: 'v1',
        role: 'User',
        courses: const [],
        createdAt: _now,
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        fineIscrizione: Timestamp.fromDate(_now.add(const Duration(days: 5))),
      );

      final result = usersByExpiringSubscriptionDuration([v1], now: _now);

      expect(result.every((e) => e.value.isEmpty), isTrue);
    });
  });
}
