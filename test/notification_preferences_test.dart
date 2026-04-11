import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Notification Preferences Tests', () {
    group('Default values', () {
      test('should have email notifications enabled by default', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
        );

        expect(user.emailNotificationsEnabled, true);
      });

      test('should have push notifications enabled by default', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
        );

        expect(user.pushNotificationsEnabled, true);
      });
    });

    group('Explicit values', () {
      test('should allow disabling email notifications', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
          emailNotificationsEnabled: false,
        );

        expect(user.emailNotificationsEnabled, false);
        expect(user.pushNotificationsEnabled, true);
      });

      test('should allow disabling push notifications', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
          pushNotificationsEnabled: false,
        );

        expect(user.emailNotificationsEnabled, true);
        expect(user.pushNotificationsEnabled, false);
      });

      test('should allow disabling both notifications', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
          emailNotificationsEnabled: false,
          pushNotificationsEnabled: false,
        );

        expect(user.emailNotificationsEnabled, false);
        expect(user.pushNotificationsEnabled, false);
      });
    });

    group('Serialization toJson', () {
      test('should serialize notification preferences', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
          emailNotificationsEnabled: false,
          pushNotificationsEnabled: true,
        );

        final json = user.toJson();

        expect(json['emailNotificationsEnabled'], false);
        expect(json['pushNotificationsEnabled'], true);
      });

      test('should serialize default notification preferences', () {
        final user = FitropeUser(
          uid: 'user-1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
        );

        final json = user.toJson();

        expect(json['emailNotificationsEnabled'], true);
        expect(json['pushNotificationsEnabled'], true);
      });
    });

    group('Deserialization fromJson', () {
      test('should deserialize notification preferences', () {
        final json = {
          'uid': 'user-1',
          'email': 'test@example.com',
          'name': 'Test',
          'lastName': 'User',
          'courses': <String>[],
          'role': 'User',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'emailNotificationsEnabled': false,
          'pushNotificationsEnabled': false,
        };

        final user = FitropeUser.fromJson(json);

        expect(user.emailNotificationsEnabled, false);
        expect(user.pushNotificationsEnabled, false);
      });

      test('should default to true when fields are missing (legacy users)', () {
        final json = {
          'uid': 'user-legacy',
          'email': 'legacy@example.com',
          'name': 'Legacy',
          'lastName': 'User',
          'courses': <String>[],
          'role': 'User',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          // Nessun campo notifiche — simula un utente esistente prima della feature
        };

        final user = FitropeUser.fromJson(json);

        expect(user.emailNotificationsEnabled, true);
        expect(user.pushNotificationsEnabled, true);
      });

      test('should default to true when fields are null', () {
        final json = {
          'uid': 'user-null',
          'email': 'null@example.com',
          'name': 'Null',
          'lastName': 'User',
          'courses': <String>[],
          'role': 'User',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'emailNotificationsEnabled': null,
          'pushNotificationsEnabled': null,
        };

        final user = FitropeUser.fromJson(json);

        expect(user.emailNotificationsEnabled, true);
        expect(user.pushNotificationsEnabled, true);
      });
    });

    group('Round-trip serialization', () {
      test('should preserve notification preferences through toJson/fromJson', () {
        final original = FitropeUser(
          uid: 'user-roundtrip',
          email: 'roundtrip@example.com',
          name: 'Round',
          lastName: 'Trip',
          courses: ['course-1'],
          role: 'User',
          createdAt: DateTime.now(),
          emailNotificationsEnabled: false,
          pushNotificationsEnabled: true,
        );

        final json = original.toJson();
        final deserialized = FitropeUser.fromJson(json);

        expect(deserialized.emailNotificationsEnabled, original.emailNotificationsEnabled);
        expect(deserialized.pushNotificationsEnabled, original.pushNotificationsEnabled);
      });

      test('should preserve all fields including notifications through round-trip', () {
        final original = FitropeUser(
          uid: 'user-full',
          email: 'full@example.com',
          name: 'Full',
          lastName: 'User',
          courses: ['c1', 'c2'],
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateSettimanali: 3,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          createdAt: DateTime.now(),
          waitlistCourses: ['c3'],
          emailNotificationsEnabled: false,
          pushNotificationsEnabled: false,
        );

        final json = original.toJson();
        final deserialized = FitropeUser.fromJson(json);

        expect(deserialized.uid, original.uid);
        expect(deserialized.courses, original.courses);
        expect(deserialized.waitlistCourses, original.waitlistCourses);
        expect(deserialized.emailNotificationsEnabled, false);
        expect(deserialized.pushNotificationsEnabled, false);
      });
    });
  });
}
