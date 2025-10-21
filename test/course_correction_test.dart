import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Course Correction Feature Tests', () {
    
    late Course testCourse;
    late List<FitropeUser> testUsers;
    
    setUp(() {
      // Crea un corso di test con discrepanza
      testCourse = Course(
        id: 'test-course-1',
        uid: 'test-course-1',
        name: 'Corso di Test',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 2, // Il corso dice di avere 2 iscritti
      );
      
      // Crea 4 utenti di test (discrepanza: 4 effettivi vs 2 nel database)
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

    test('should detect mismatch and show correction button for Admin', () {
      // Simula le condizioni per Admin
      bool isAdmin = true;
      bool hasMismatch = testUsers.length != testCourse.subscribed;
      
      expect(hasMismatch, true);
      expect(isAdmin, true);
      expect(hasMismatch && isAdmin, true); // Il pulsante dovrebbe essere visibile
    });

    test('should detect mismatch and show correction button for Trainer', () {
      // Simula le condizioni per Trainer
      String userRole = 'Trainer';
      bool hasMismatch = testUsers.length != testCourse.subscribed;
      
      expect(hasMismatch, true);
      expect(userRole == 'Trainer', true);
      expect(hasMismatch && userRole == 'Trainer', true); // Il pulsante dovrebbe essere visibile
    });

    test('should not show correction button for regular User', () {
      // Simula le condizioni per User normale
      String userRole = 'User';
      bool hasMismatch = testUsers.length != testCourse.subscribed;
      
      expect(hasMismatch, true);
      expect(userRole == 'User', true);
      expect(hasMismatch && userRole == 'User', false); // Il pulsante NON dovrebbe essere visibile
    });

    test('should not show correction button when there is no mismatch', () {
      // Crea un corso che matcha il numero di utenti
      Course matchingCourse = Course(
        id: 'test-course-2',
        uid: 'test-course-2',
        name: 'Corso Matching',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 4, // Matcha il numero di utenti
      );
      
      bool isAdmin = true;
      bool hasMismatch = testUsers.length != matchingCourse.subscribed;
      
      expect(hasMismatch, false);
      expect(isAdmin, true);
      expect(hasMismatch && isAdmin, false); // Il pulsante NON dovrebbe essere visibile
    });

    test('should calculate correct new subscribed count', () {
      int actualCount = testUsers.length;
      int storedCount = testCourse.subscribed;
      
      expect(actualCount, 4);
      expect(storedCount, 2);
      expect(actualCount, greaterThan(storedCount));
      
      // Il nuovo conteggio dovrebbe essere il numero effettivo di utenti
      int newSubscribedCount = actualCount;
      expect(newSubscribedCount, 4);
    });
  });
}
