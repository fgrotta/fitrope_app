import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/course_tags.dart';

void main() {
  final start = Timestamp.fromDate(DateTime(2026, 1, 1));
  final end = Timestamp.fromDate(DateTime(2026, 2, 1));

  group('UserSubscription serialization', () {
    test('roundtrip FREQUENCY illimitato (weeklyFrequency null)', () {
      final s = UserSubscription(
        planKey: 'open_unlim_1m',
        family: SubscriptionFamily.OPEN,
        billingMode: BillingMode.FREQUENCY,
        courseTypeTags: {CourseTags.OPEN},
        weeklyFrequency: null,
        startDate: start,
        endDate: end,
      );
      final r = UserSubscription.fromJson(s.toJson());
      expect(r.family, SubscriptionFamily.OPEN);
      expect(r.billingMode, BillingMode.FREQUENCY);
      expect(r.weeklyFrequency, isNull);
      expect(r.courseTypeTags, {CourseTags.OPEN});
      expect(r.endDate, end);
    });

    test('roundtrip ENTRIES', () {
      final s = UserSubscription(
        planKey: 'open_10i_3m',
        family: SubscriptionFamily.OPEN,
        billingMode: BillingMode.ENTRIES,
        courseTypeTags: {CourseTags.OPEN},
        remainingEntries: 10,
        startDate: start,
        endDate: end,
      );
      final r = UserSubscription.fromJson(s.toJson());
      expect(r.family, SubscriptionFamily.OPEN);
      expect(r.billingMode, BillingMode.ENTRIES);
      expect(r.remainingEntries, 10);
    });

    test('roundtrip preserva id e startDate', () {
      final s = UserSubscription(
        id: 'sub-123',
        planKey: 'open_2x_3m',
        family: SubscriptionFamily.OPEN,
        billingMode: BillingMode.FREQUENCY,
        courseTypeTags: {CourseTags.OPEN},
        weeklyFrequency: 2,
        startDate: start,
        endDate: end,
      );
      final r = UserSubscription.fromJson(s.toJson());
      expect(r.id, 'sub-123');
      expect(r.startDate, start);
    });

    test('rifiuta planKey sconosciuta o incoerente con famiglia/modalita', () {
      Map<String, dynamic> json({
        required String planKey,
        String family = 'OPEN',
        String billingMode = 'FREQUENCY',
      }) =>
          {
            'planKey': planKey,
            'family': family,
            'billingMode': billingMode,
            'startDate': start,
            'endDate': end,
          };

      expect(
        () => UserSubscription.fromJson(json(planKey: 'legacy_unknown')),
        throwsFormatException,
      );
      expect(
        () => UserSubscription.fromJson(
          {
            ...json(planKey: 'pt_10i_1m', family: 'OPEN'),
            'courseTypeTags': ['Open'],
            'weeklyFrequency': null,
            'remainingEntries': 10,
          },
        ),
        throwsFormatException,
      );
    });
  });

  group('FitropeUser.activeSubscriptions serialization', () {
    test('roundtrip preserva gli abbonamenti', () {
      final user = FitropeUser(
        uid: 'u',
        email: 'e',
        name: 'N',
        lastName: 'C',
        courses: const [],
        role: 'User',
        createdAt: DateTime(2026, 1, 1),
        activeSubscriptions: [
          UserSubscription(
            planKey: 'pt_10i_6m',
            family: SubscriptionFamily.PT,
            billingMode: BillingMode.ENTRIES,
            courseTypeTags: {CourseTags.PERSONAL_TRAINER},
            remainingEntries: 7,
            startDate: start,
            endDate: end,
          ),
        ],
      );
      final r = FitropeUser.fromJson(user.toJson());
      expect(r.activeSubscriptions.length, 1);
      expect(r.activeSubscriptions.first.family, SubscriptionFamily.PT);
      expect(r.activeSubscriptions.first.remainingEntries, 7);
    });

    test('utente legacy senza activeSubscriptions -> lista vuota', () {
      final r = FitropeUser.fromJson({
        'uid': 'u',
        'email': 'e',
        'name': 'N',
        'lastName': 'C',
      });
      expect(r.activeSubscriptions, isEmpty);
    });

    test('uno snapshot malformato fallisce senza ricadere sul legacy', () {
      expect(
        () => FitropeUser.fromJson({
          'uid': 'u',
          'email': 'e',
          'name': 'N',
          'lastName': 'C',
          'activeSubscriptions': [
            {
              'planKey': 'bad',
              'family': 'FAMIGLIA_SCONOSCIUTA',
              'billingMode': 'FREQUENCY',
              'startDate': start,
              'endDate': end,
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
