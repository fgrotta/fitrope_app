import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/utils/course_tags.dart';

void main() {
  group('SubscriptionPlans catalogo', () {
    test('conteggi: 12 Open + 4 Hyrox + 4 PT = 20', () {
      expect(SubscriptionPlans.open.length, 12);
      expect(SubscriptionPlans.hyrox.length, 4);
      expect(SubscriptionPlans.pt.length, 4);
      expect(SubscriptionPlans.all.length, 20);
    });

    test('chiavi univoche', () {
      final keys = SubscriptionPlans.all.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('Open: per ogni durata esistono frequenze {2, 3, illimitato}', () {
      for (final d in SubscriptionPlans.durations) {
        final forD =
            SubscriptionPlans.open.where((p) => p.durationMonths == d).toList();
        expect(forD.map((p) => p.weeklyFrequency).toSet(), {2, 3, null});
        expect(forD.every((p) => p.billingMode == BillingMode.FREQUENCY), true);
        expect(
            forD.every(
                (p) => p.grantedCourseTypeTags.contains(CourseTags.OPEN)),
            true);
      }
    });

    test('Hyrox/PT: 10 ingressi, modalità ENTRIES, tag corretti', () {
      expect(
          SubscriptionPlans.hyrox.every((p) =>
              p.entries == 10 &&
              p.billingMode == BillingMode.ENTRIES &&
              p.grantedCourseTypeTags.contains(CourseTags.HYROX)),
          true);
      expect(
          SubscriptionPlans.pt.every((p) =>
              p.entries == 10 &&
              p.billingMode == BillingMode.ENTRIES &&
              p.grantedCourseTypeTags.contains(CourseTags.PERSONAL_TRAINER)),
          true);
    });

    test('durate sempre in {1, 3, 6, 12}', () {
      expect(
          SubscriptionPlans.all
              .every((p) => const {1, 3, 6, 12}.contains(p.durationMonths)),
          true);
    });

    test('byKey risolve i piani noti e ritorna null per gli sconosciuti', () {
      expect(
          SubscriptionPlans.byKey(SubscriptionPlans.all.first.key), isNotNull);
      expect(SubscriptionPlans.byKey('inesistente'), isNull);
    });
  });
}
