import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/user_display_utils.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('UserDisplayUtils Tests', () {
    test(
        'getDisplayName should return correct format for admin with valid user',
        () {
      final user = FitropeUser(
        uid: 'test-uid',
        email: 'test@example.com',
        name: 'Mario',
        lastName: 'Rossi',
        courses: [],
        role: 'User',
        createdAt: DateTime.now(),
        fineIscrizione: Timestamp.fromDate(
            DateTime.now().add(Duration(days: 30))), // Abbonamento valido
      );

      final displayName = UserDisplayUtils.getDisplayName(user, true);
      expect(displayName, equals('Mario Rossi'));
    });

    test(
        'getDisplayName should return correct format for admin with anonymous user',
        () {
      final user = FitropeUser(
        uid: 'test-uid',
        email: 'test@example.com',
        name: 'Mario',
        lastName: 'Rossi',
        courses: [],
        role: 'User',
        createdAt: DateTime.now(),
        isAnonymous: true,
      );

      final displayName = UserDisplayUtils.getDisplayName(user, true);
      expect(displayName, equals('Mario Rossi - (Anonimo)'));
    });

    test('getDisplayName should return correct format for non-admin', () {
      final user = FitropeUser(
        uid: 'test-uid',
        email: 'test@example.com',
        name: 'Mario',
        lastName: 'Rossi',
        courses: [],
        role: 'User',
        createdAt: DateTime.now(),
      );

      final displayName = UserDisplayUtils.getDisplayName(user, false);
      expect(displayName, equals('Mario Rossi'));
    });

    test(
        'getDisplayName should return anonymous format for non-admin with anonymous user',
        () {
      final user = FitropeUser(
        uid: 'test-uid',
        email: 'test@example.com',
        name: 'Mario',
        lastName: 'Rossi',
        courses: [],
        role: 'User',
        createdAt: DateTime.now(),
        isAnonymous: true,
      );

      final displayName = UserDisplayUtils.getDisplayName(user, false);
      expect(displayName, equals('(Anonimo)'));
    });
  });
}
