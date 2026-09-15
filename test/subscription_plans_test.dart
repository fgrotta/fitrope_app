import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/utils/course_tags.dart';

void main() {
  group('SubscriptionPlans catalogo', () {
    test('conteggi: 16 Open + 4 PT = 20', () {
      expect(SubscriptionPlans.open.length, 16);
      expect(SubscriptionPlans.pt.length, 4);
      expect(SubscriptionPlans.all.length, 20);
    });

    test('chiavi univoche e nessun piano Hyrox', () {
      final keys = SubscriptionPlans.all.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.where((key) => key.startsWith('hyrox_')), isEmpty);
    });

    test('Open: frequenze {2,3,illimitato} e pacchetto 10 ingressi', () {
      for (final d in SubscriptionPlans.durations) {
        final forD =
            SubscriptionPlans.open.where((p) => p.durationMonths == d).toList();
        final frequency =
            forD.where((p) => p.billingMode == BillingMode.FREQUENCY);
        expect(frequency.map((p) => p.weeklyFrequency).toSet(), {2, 3, null});
        expect(
          forD
              .where((p) => p.billingMode == BillingMode.ENTRIES)
              .single
              .entries,
          10,
        );
        expect(
          forD.every(
              (p) => p.grantedCourseTypeTags.toSet().equals({CourseTags.OPEN})),
          true,
        );
      }
    });

    test('PT: 10 ingressi, modalita ENTRIES', () {
      expect(
          SubscriptionPlans.pt.every((p) =>
              p.entries == 10 &&
              p.billingMode == BillingMode.ENTRIES &&
              p.grantedCourseTypeTags.contains(CourseTags.PERSONAL_TRAINER)),
          true);
    });

    test('byKey e parser catalogo sono stretti', () {
      expect(SubscriptionPlans.byKey('open_10i_3m'), isNotNull);
      expect(SubscriptionPlans.byKey('hyrox_10i_3m'), isNull);
      expect(SubscriptionPlans.byKey('inesistente'), isNull);
    });
  });
}

extension on Set<String> {
  bool equals(Set<String> other) =>
      length == other.length && other.every((value) => this.contains(value));
}
