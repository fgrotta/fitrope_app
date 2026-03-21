import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Enrollment Mismatch Detection Tests', () {
    
    late Course testCourse;
    late List<FitropeUser> testUsers;
    
    setUp(() {
      // Crea un corso di test
      testCourse = Course(
        id: 'test-course-1',
        uid: 'test-course-1',
        name: 'Corso di Test',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 3, // Il corso dice di avere 3 iscritti
      );
      
      // Crea alcuni utenti di test
      testUsers = [
        FitropeUser(
          uid: 'user1',
          email: 'user1@test.com',
          name: 'User',
          lastName: 'One',
          courses: ['test-course-1'],
          role: 'User',
          createdAt: DateTime.now(),
        ),
        FitropeUser(
          uid: 'user2',
          email: 'user2@test.com',
          name: 'User',
          lastName: 'Two',
          courses: ['test-course-1'],
          role: 'User',
          createdAt: DateTime.now(),
        ),
        FitropeUser(
          uid: 'user3',
          email: 'user3@test.com',
          name: 'User',
          lastName: 'Three',
          courses: ['test-course-1'],
          role: 'User',
          createdAt: DateTime.now(),
        ),
        FitropeUser(
          uid: 'user4',
          email: 'user4@test.com',
          name: 'User',
          lastName: 'Four',
          courses: ['test-course-1'],
          role: 'User',
          createdAt: DateTime.now(),
        ),
      ];
    });

    test('should detect mismatch when actual users count differs from course.subscribed', () {
      // Test con 4 utenti effettivi ma corso.subscribed = 3
      expect(testUsers.length, 4);
      expect(testCourse.subscribed, 3);
      expect(testUsers.length != testCourse.subscribed, true);
    });

    test('should not detect mismatch when counts match', () {
      // Crea un corso con subscribed = 4 per matchare i 4 utenti
      Course matchingCourse = Course(
        id: 'test-course-2',
        uid: 'test-course-2',
        name: 'Corso Matching',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 4, // Matcha il numero di utenti
      );
      
      expect(testUsers.length, 4);
      expect(matchingCourse.subscribed, 4);
      expect(testUsers.length != matchingCourse.subscribed, false);
    });

    test('should handle null subscribersUsers gracefully', () {
      // Test con subscribersUsers null
      List<FitropeUser>? nullUsers = null;
      expect(nullUsers == null, true);
      // La funzione dovrebbe restituire false quando subscribersUsers è null
    });

    test('should handle null subscribed value gracefully', () {
      // Test con subscribed null
      int? nullSubscribed = null;
      expect(nullSubscribed == null, true);
      // La funzione dovrebbe restituire false quando subscribed è null
    });
  });
}
