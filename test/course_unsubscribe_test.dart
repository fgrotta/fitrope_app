import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('CourseUnsubscribeHelper Tests', () {
    
    late Course testCourse;
    late Course courseSoon;
    late Course courseExact;
    late Course coursePast;
    late FitropeUser testUserPacchetto;
    late FitropeUser testUserAbbonamento;
    
    setUp(() {
      // Crea un corso di test che inizia tra 10 ore (> 8 ore)
      testCourse = Course(
        id: 'test-course-1',
        uid: 'test-course-1',
        name: 'Corso di Test',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso che inizia tra 6 ore (< 8 ore)
      courseSoon = Course(
        id: 'test-course-soon',
        uid: 'test-course-soon',
        name: 'Corso Imminente',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 6))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 7))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso che inizia esattamente tra 8 ore (= 8 ore)
      courseExact = Course(
        id: 'test-course-exact',
        uid: 'test-course-exact',
        name: 'Corso Esatto',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 8))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 9))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso che è già iniziato
      coursePast = Course(
        id: 'test-course-past',
        uid: 'test-course-past',
        name: 'Corso Passato',
        startDate: Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Utente con Pacchetto Entrate
      testUserPacchetto = FitropeUser(
        uid: 'user-pacchetto',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: ['test-course-1', 'test-course-soon', 'test-course-exact', 'test-course-past'],
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 5,
        entrateSettimanali: null,
        fineIscrizione: null,
        role: 'User',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
      
      // Utente con Abbonamento Mensile
      testUserAbbonamento = FitropeUser(
        uid: 'user-abbonamento',
        email: 'test2@example.com',
        name: 'Test',
        lastName: 'User2',
        courses: ['test-course-1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateDisponibili: null,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        role: 'User',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
    });
    
    group('canUnsubscribe', () {
      test('should return false for user not subscribed to course', () {
        final userNotSubscribed = FitropeUser(
          uid: 'user-not-subscribed',
          email: 'test3@example.com',
          name: 'Test',
          lastName: 'User3',
          courses: [],
          tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: 5,
          entrateSettimanali: null,
          fineIscrizione: null,
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(testCourse, userNotSubscribed);
        
        expect(result['canUnsubscribe'], false);
        expect(result['message'], 'Non sei iscritto a questo corso');
      });
      
      test('should return true for Pacchetto Entrate with > 8 hours remaining', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(testCourse, testUserPacchetto);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], false);
        expect(result['isPacchettoEntrate'], true);
        expect(result['message'], 'Disiscrizione: il credito ti sarà rimborsato');
        expect(result['hoursRemaining'], greaterThan(8));
      });
      
      test('should return true for Pacchetto Entrate with < 8 hours remaining', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseSoon, testUserPacchetto);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['isPacchettoEntrate'], true);
        expect(result['message'], 'Disiscrizione a meno di 8 ore: perderai il credito');
        expect(result['hoursRemaining'], lessThan(8));
      });
      
      test('should return true for Pacchetto Entrate with exactly 8 hours remaining', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseExact, testUserPacchetto);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['isPacchettoEntrate'], true);
        expect(result['message'], 'Disiscrizione a meno di 8 ore: perderai il credito');
        expect(result['hoursRemaining'], 8);
      });
      
      test('should return true for Pacchetto Entrate with course already started', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(coursePast, testUserPacchetto);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['isPacchettoEntrate'], true);
        expect(result['message'], 'Disiscrizione a meno di 8 ore: perderai il credito');
        expect(result['hoursRemaining'], lessThan(0));
      });
      
      test('should return true for Abbonamento without confirmation requirement', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(testCourse, testUserAbbonamento);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], false);
        expect(result['isPacchettoEntrate'], false);
        expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
      });
    });
    
    group('Edge Cases', () {
      test('should handle course starting in exactly 8 hours', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseExact, testUserPacchetto);
        
        expect(result['requiresConfirmation'], true);
        expect(result['hoursRemaining'], 8);
      });
      
      test('should handle course starting in the past', () {
        final result = CourseUnsubscribeHelper.canUnsubscribe(coursePast, testUserPacchetto);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['hoursRemaining'], lessThan(0));
      });
      
      test('should handle course starting in exactly 7 hours and 59 minutes', () {
        final courseAlmost8 = Course(
          id: 'test-course-almost-8',
          uid: 'test-course-almost-8',
          name: 'Corso Quasi 8 Ore',
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 7, minutes: 59))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 8, minutes: 59))),
          capacity: 20,
          subscribed: 5,
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseAlmost8, testUserPacchetto);
        
        expect(result['requiresConfirmation'], true);
        expect(result['hoursRemaining'], 7);
      });
      
      test('should handle course starting in exactly 8 hours and 1 minute', () {
        final courseJustOver8 = Course(
          id: 'test-course-just-over-8',
          uid: 'test-course-just-over-8',
          name: 'Corso Appena Oltre 8 Ore',
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 8, minutes: 1))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 9, minutes: 1))),
          capacity: 20,
          subscribed: 5,
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseJustOver8, testUserPacchetto);
        
        expect(result['requiresConfirmation'], false);
        expect(result['hoursRemaining'], 8);
      });
    });
  });
}
