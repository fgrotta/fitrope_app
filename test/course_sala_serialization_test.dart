import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/sale.dart';

void main() {
  final start = Timestamp.fromDate(DateTime(2026, 1, 1, 10));
  final end = Timestamp.fromDate(DateTime(2026, 1, 1, 11));

  Course buildCourse({String? sala}) => Course(
        id: 'c1',
        uid: 'c1',
        name: 'Test',
        startDate: start,
        endDate: end,
        capacity: 10,
        subscribed: 0,
        sala: sala,
      );

  group('Course.sala serialization', () {
    test('toJson include la sala', () {
      expect(buildCourse(sala: Sale.SALA_1).toJson()['sala'], Sale.SALA_1);
    });

    test('roundtrip toJson/fromJson preserva la sala', () {
      final restored = Course.fromJson(buildCourse(sala: Sale.SALA_2).toJson());
      expect(restored.sala, Sale.SALA_2);
    });

    test('fromJson senza sala (corso legacy) ritorna null', () {
      final restored = Course.fromJson({
        'uid': 'c1',
        'name': 'Legacy',
        'startDate': start,
        'endDate': end,
        'capacity': 10,
        'subscribed': 0,
      });
      expect(restored.sala, isNull);
    });

    test('sala null non rompe il roundtrip', () {
      final restored = Course.fromJson(buildCourse().toJson());
      expect(restored.sala, isNull);
    });
  });

  group('Course.copyWith (logica usata da createCourse)', () {
    Course fullCourse() => Course(
          id: 'orig',
          uid: 'orig',
          name: 'Corso',
          startDate: start,
          endDate: end,
          capacity: 8,
          subscribed: 3,
          trainerId: 't1',
          tags: const ['Hyrox'],
          waitlist: const ['u1'],
          reminderEnabled: false,
          waitlistEnabled: false,
          sala: Sale.SALA_1,
        );

    test('override di uid/id preserva tutti gli altri campi', () {
      final copy = fullCourse().copyWith(uid: 'newid', id: 'newid');
      expect(copy.uid, 'newid');
      expect(copy.id, 'newid');
      expect(copy.name, 'Corso');
      expect(copy.capacity, 8);
      expect(copy.subscribed, 3);
      expect(copy.trainerId, 't1');
      expect(copy.tags, const ['Hyrox']);
      expect(copy.waitlist, const ['u1']);
      // I campi che createCourse perdeva in passato (forzati ai default):
      expect(copy.reminderEnabled, false);
      expect(copy.waitlistEnabled, false);
      expect(copy.sala, Sale.SALA_1);
    });

    test('copyWith senza argomenti è equivalente all\'originale', () {
      final original = fullCourse();
      expect(original.copyWith().toJson(), original.toJson());
    });

    test('id rispecchia uid quando si sovrascrive solo uid', () {
      final copy = fullCourse().copyWith(uid: 'x');
      expect(copy.uid, 'x');
      expect(copy.id, 'x');
    });

    test('copyWith(sala: null) azzera la sala', () {
      expect(fullCourse().copyWith(sala: null).sala, isNull);
    });

    test('copyWith senza sala la preserva', () {
      expect(fullCourse().copyWith(name: 'Altro').sala, Sale.SALA_1);
    });

    test('copyWith(trainerId: null) azzera il trainer', () {
      expect(fullCourse().copyWith(trainerId: null).trainerId, isNull);
    });
  });
}
