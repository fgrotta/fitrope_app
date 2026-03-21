import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';

Course _makeCourse(DateTime start, DateTime end) => Course(
      id: 'test',
      uid: 'test',
      name: 'Test',
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(end),
      capacity: 10,
      subscribed: 0,
    );

void main() {
  group('getCourseTimeRange', () {
    test('formats a standard time range', () {
      final start = DateTime(2024, 3, 15, 10, 0);
      final end = DateTime(2024, 3, 15, 11, 0);
      expect(getCourseTimeRange(_makeCourse(start, end)), '10:00 - 11:00');
    });

    test('pads single-digit hours and minutes with leading zero', () {
      final start = DateTime(2024, 3, 15, 9, 5);
      final end = DateTime(2024, 3, 15, 9, 45);
      expect(getCourseTimeRange(_makeCourse(start, end)), '09:05 - 09:45');
    });

    test('formats midnight correctly', () {
      final start = DateTime(2024, 3, 15, 0, 0);
      final end = DateTime(2024, 3, 15, 1, 30);
      expect(getCourseTimeRange(_makeCourse(start, end)), '00:00 - 01:30');
    });

    test('formats end of day correctly', () {
      final start = DateTime(2024, 3, 15, 22, 30);
      final end = DateTime(2024, 3, 15, 23, 59);
      expect(getCourseTimeRange(_makeCourse(start, end)), '22:30 - 23:59');
    });

    test('handles course spanning hours', () {
      final start = DateTime(2024, 3, 15, 7, 15);
      final end = DateTime(2024, 3, 15, 8, 45);
      expect(getCourseTimeRange(_makeCourse(start, end)), '07:15 - 08:45');
    });
  });
}
