import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';

UserSubscription _sub({
  String planKey = 'open_2x_1m',
  SubscriptionFamily family = SubscriptionFamily.OPEN,
  BillingMode billingMode = BillingMode.FREQUENCY,
  Set<String>? courseTypeTags,
  int? weeklyFrequency = 2,
  int? remainingEntries,
  DateTime? start,
  DateTime? end,
}) {
  return UserSubscription(
    planKey: planKey,
    family: family,
    billingMode: billingMode,
    courseTypeTags: courseTypeTags ?? {CourseTags.OPEN},
    weeklyFrequency: weeklyFrequency,
    remainingEntries: remainingEntries,
    startDate: Timestamp.fromDate(start ?? DateTime(2026, 1, 1)),
    endDate: Timestamp.fromDate(end ?? DateTime(2026, 12, 31)),
  );
}

void main() {
  group('getSubscriptionFamilyLabel', () {
    test('etichetta per ogni famiglia', () {
      expect(getSubscriptionFamilyLabel(SubscriptionFamily.OPEN), 'Open');
      expect(getSubscriptionFamilyLabel(SubscriptionFamily.HYROX), 'Hyrox');
      expect(getSubscriptionFamilyLabel(SubscriptionFamily.PT),
          'Personal Trainer');
    });
  });

  group('getSubscriptionTitle', () {
    test('piano noto -> displayName del catalogo', () {
      expect(getSubscriptionTitle(_sub(planKey: 'open_unlim_12m')),
          'Open illimitato · 12 mesi');
      expect(getSubscriptionTitle(_sub(planKey: 'open_3x_1m', weeklyFrequency: 3)),
          'Open 3 volte/sett · 1 mese');
      expect(
          getSubscriptionTitle(_sub(
            planKey: 'hyrox_10i_3m',
            family: SubscriptionFamily.HYROX,
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: 10,
          )),
          'Hyrox 10 ingressi · 3 mesi');
    });

    test('piano noto: il displayName del catalogo prevale su snapshot incoerente',
        () {
      // weeklyFrequency/residui arbitrari e diversi dal piano: il titolo resta
      // quello del catalogo (lo snapshot non sovrascrive il titolo).
      expect(
          getSubscriptionTitle(_sub(
            planKey: 'open_unlim_12m',
            weeklyFrequency: 99,
            remainingEntries: 123,
          )),
          'Open illimitato · 12 mesi');
    });

    test('piano fuori catalogo -> fallback famiglia + variante STABILE', () {
      // FREQUENCY illimitato fuori catalogo.
      expect(
          getSubscriptionTitle(_sub(planKey: 'piano_inesistente', weeklyFrequency: null)),
          'Open · illimitato');
      // FREQUENCY 2x fuori catalogo.
      expect(getSubscriptionTitle(_sub(planKey: 'fuori', weeklyFrequency: 2)),
          'Open · 2 volte/sett');
      // FREQUENCY 1x fuori catalogo -> singolare nel descrittore di variante.
      expect(getSubscriptionTitle(_sub(planKey: 'fuori', weeklyFrequency: 1)),
          'Open · 1 volta/sett');
      // ENTRIES fuori catalogo: NON include il conteggio residui nel titolo
      // (evita duplicazione con la riga allowance della card).
      expect(
          getSubscriptionTitle(_sub(
            planKey: 'pt_legacy',
            family: SubscriptionFamily.PT,
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: 4,
          )),
          'Personal Trainer · pacchetto ingressi');
      // ENTRIES fuori catalogo con HYROX e residui null.
      expect(
          getSubscriptionTitle(_sub(
            planKey: 'fuori',
            family: SubscriptionFamily.HYROX,
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: null,
          )),
          'Hyrox · pacchetto ingressi');
    });
  });

  group('getSubscriptionAllowanceLabel', () {
    test('ENTRIES -> ingressi residui (null -> 0, negativi -> 0)', () {
      expect(
          getSubscriptionAllowanceLabel(_sub(
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: 7,
          )),
          'Ingressi residui: 7');
      expect(
          getSubscriptionAllowanceLabel(_sub(
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: null,
          )),
          'Ingressi residui: 0');
      expect(
          getSubscriptionAllowanceLabel(_sub(
            billingMode: BillingMode.ENTRIES,
            weeklyFrequency: null,
            remainingEntries: -1,
          )),
          'Ingressi residui: 0');
    });

    test('FREQUENCY -> volte a settimana, plurale/singolare e illimitato', () {
      expect(getSubscriptionAllowanceLabel(_sub(weeklyFrequency: 2)),
          '2 volte a settimana');
      expect(getSubscriptionAllowanceLabel(_sub(weeklyFrequency: 3)),
          '3 volte a settimana');
      expect(getSubscriptionAllowanceLabel(_sub(weeklyFrequency: 1)),
          '1 volta a settimana');
      expect(getSubscriptionAllowanceLabel(_sub(weeklyFrequency: null)),
          'Accessi illimitati');
    });
  });

  group('getSubscriptionExpiryLabel', () {
    test('data formattata in italiano esteso (boundary mese)', () {
      expect(getSubscriptionExpiryLabel(_sub(end: DateTime(2026, 3, 5))),
          'Scadenza: 5 Marzo 2026');
      expect(getSubscriptionExpiryLabel(_sub(end: DateTime(2026, 1, 1))),
          'Scadenza: 1 Gennaio 2026');
      expect(getSubscriptionExpiryLabel(_sub(end: DateTime(2026, 12, 31))),
          'Scadenza: 31 Dicembre 2026');
    });
  });

  group('getSubscriptionStatusLabel', () {
    final now = DateTime(2026, 6, 13, 12);

    test('scaduto / oggi / domani (singolare) / pochi giorni / valido', () {
      expect(
          getSubscriptionStatusLabel(_sub(end: now.subtract(const Duration(seconds: 1))), now: now),
          'Scaduto');
      // endDate == now -> non ancora scaduto, 0 giorni -> "Scade oggi".
      expect(getSubscriptionStatusLabel(_sub(end: now), now: now), 'Scade oggi');
      // ~1.5 giorni -> inDays tronca a 1 -> singolare.
      expect(
          getSubscriptionStatusLabel(_sub(end: now.add(const Duration(days: 1, hours: 12))), now: now),
          'Scade tra 1 giorno');
      expect(
          getSubscriptionStatusLabel(_sub(end: now.add(const Duration(days: 5))), now: now),
          'Scade tra 5 giorni');
      // Oltre la soglia (15 gg) -> "Valido".
      expect(
          getSubscriptionStatusLabel(_sub(end: now.add(const Duration(days: 40))), now: now),
          'Valido');
    });

    test('confine soglia "in scadenza" (15 gg): 15 dentro, 16 -> Valido', () {
      expect(
          getSubscriptionStatusLabel(_sub(end: now.add(const Duration(days: 15, hours: 1))), now: now),
          'Scade tra 15 giorni');
      expect(
          getSubscriptionStatusLabel(_sub(end: now.add(const Duration(days: 16, hours: 1))), now: now),
          'Valido');
    });

    test('ENTRIES esaurito (residui <=0 ma non scaduto) -> "Esaurito"', () {
      // Vale anche con endDate lontana: il pacchetto è inutilizzabile.
      expect(
          getSubscriptionStatusLabel(
              _sub(
                billingMode: BillingMode.ENTRIES,
                weeklyFrequency: null,
                remainingEntries: 0,
                end: now.add(const Duration(days: 40)),
              ),
              now: now),
          'Esaurito');
      expect(
          getSubscriptionStatusLabel(
              _sub(
                billingMode: BillingMode.ENTRIES,
                weeklyFrequency: null,
                remainingEntries: null,
                end: now.add(const Duration(days: 40)),
              ),
              now: now),
          'Esaurito');
      // Con residui disponibili NON è esaurito.
      expect(
          getSubscriptionStatusLabel(
              _sub(
                billingMode: BillingMode.ENTRIES,
                weeklyFrequency: null,
                remainingEntries: 3,
                end: now.add(const Duration(days: 40)),
              ),
              now: now),
          'Valido');
      // ENTRIES esaurito MA già scaduto -> prevale "Scaduto".
      expect(
          getSubscriptionStatusLabel(
              _sub(
                billingMode: BillingMode.ENTRIES,
                weeklyFrequency: null,
                remainingEntries: 0,
                end: now.subtract(const Duration(days: 1)),
              ),
              now: now),
          'Scaduto');
    });
  });

  group('liveSubscriptions', () {
    final now = DateTime(2026, 6, 13, 12);

    test('mantiene le voci non scadute, scarta quelle scadute', () {
      final viva = _sub(planKey: 'viva', end: DateTime(2026, 7, 1));
      final scaduta = _sub(planKey: 'scaduta', end: DateTime(2026, 6, 1));
      final result = liveSubscriptions([viva, scaduta], now: now);
      expect(result.map((s) => s.planKey), ['viva']);
    });

    test('endDate uguale a now è ancora viva (now NON dopo endDate)', () {
      expect(liveSubscriptions([_sub(end: now)], now: now), hasLength(1));
    });

    test('confine al secondo: -1s scaduta, +1s viva', () {
      expect(
          liveSubscriptions([_sub(end: now.subtract(const Duration(seconds: 1)))], now: now),
          isEmpty);
      expect(
          liveSubscriptions([_sub(end: now.add(const Duration(seconds: 1)))], now: now),
          hasLength(1));
    });

    test('preserva l\'ordine relativo delle voci vive (no riordino)', () {
      final a = _sub(planKey: 'a', end: now.add(const Duration(days: 1)));
      final scad = _sub(planKey: 'x', end: now.subtract(const Duration(days: 1)));
      final b = _sub(planKey: 'b', end: now.add(const Duration(days: 30)));
      final result = liveSubscriptions([a, scad, b], now: now);
      expect(result.map((s) => s.planKey), ['a', 'b']);
    });

    test('lista vuota -> vuota', () {
      expect(liveSubscriptions(const [], now: now), isEmpty);
    });
  });
}
