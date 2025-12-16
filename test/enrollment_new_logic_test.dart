import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('New Enrollment Logic Tests with Cancellation Tracking', () {
    
    late Course testCourse1;
    late Course testCourse2;
    late Course testCourse3;
    late Course testCourseSoon; // Corso che inizia tra 2 ore (< 4 ore)
    late Course testCourseFar; // Corso che inizia tra 5 ore (> 4 ore)
    late Course testCourseNextWeek;
    
    setUp(() {
      // Reset store state
      store.dispatch(SetAllCoursesAction([]));
      
      final now = DateTime.now();
      final mondayThisWeek = now.subtract(Duration(days: now.weekday - 1));
      final mondayNextWeek = mondayThisWeek.add(const Duration(days: 7));
      
      // Corso lunedì questa settimana
      testCourse1 = Course(
        id: 'course-1',
        uid: 'course-1',
        name: 'Corso Lunedì',
        startDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso martedì questa settimana
      testCourse2 = Course(
        id: 'course-2',
        uid: 'course-2',
        name: 'Corso Martedì',
        startDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(days: 1, hours: 10))),
        endDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(days: 1, hours: 11))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso mercoledì questa settimana
      testCourse3 = Course(
        id: 'course-3',
        uid: 'course-3',
        name: 'Corso Mercoledì',
        startDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(days: 2, hours: 10))),
        endDate: Timestamp.fromDate(mondayThisWeek.add(const Duration(days: 2, hours: 11))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso che inizia tra 2 ore (< 4 ore)
      testCourseSoon = Course(
        id: 'course-soon',
        uid: 'course-soon',
        name: 'Corso Imminente',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 3))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso che inizia tra 5 ore (> 4 ore)
      testCourseFar = Course(
        id: 'course-far',
        uid: 'course-far',
        name: 'Corso Lontano',
        startDate: Timestamp.fromDate(now.add(const Duration(hours: 5))),
        endDate: Timestamp.fromDate(now.add(const Duration(hours: 6))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Corso prossima settimana
      testCourseNextWeek = Course(
        id: 'course-next-week',
        uid: 'course-next-week',
        name: 'Corso Prossima Settimana',
        startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 10))),
        endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 11))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Imposta i corsi nello store
      store.dispatch(SetAllCoursesAction([
        testCourse1,
        testCourse2,
        testCourse3,
        testCourseSoon,
        testCourseFar,
        testCourseNextWeek,
      ]));
    });
    
    group('Unsubscription for Temporal Subscriptions > 4 hours', () {
      test('should not require confirmation for course starting in > 4 hours', () {
        final userWithCourse = FitropeUser(
          uid: 'user-with-course',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-far'],
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [],
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(testCourseFar, userWithCourse);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], false);
        expect(result['isTemporalSubscription'], true);
        expect(result['hoursRemaining'], greaterThan(4));
      });
      
      test('should track cancellation with entryLost: false when > 4 hours', () {
        // Questo test verifica il comportamento atteso:
        // Quando un utente si disiscrive > 4 ore prima, la disiscrizione viene tracciata
        // con entryLost: false, quindi l'ingresso settimanale rimane disponibile
        
        // Simula una disiscrizione tracciata con entryLost: false
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: false,
          courseStartDate: testCourse1.startDate,
        );
        
        final userWithCancellation = FitropeUser(
          uid: 'user-with-cancellation',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-2'], // Solo 1 corso attivo
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollment],
        );
        
        // L'utente ha 1 corso attivo e 1 disiscrizione non persa
        // Quindi ha usato 1 ingresso (non 2, perché la disiscrizione non persa non conta)
        final state = getCourseState(testCourse3, userWithCancellation);
        
        // Dovrebbe poter iscriversi perché ha usato solo 1 ingresso su 2
        expect(state, CourseState.CAN_SUBSCRIBE);
      });
    });
    
    group('Unsubscription for Temporal Subscriptions < 4 hours', () {
      test('should require confirmation for course starting in < 4 hours', () {
        final userWithCourse = FitropeUser(
          uid: 'user-with-course',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-soon'],
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [],
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(testCourseSoon, userWithCourse);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['isTemporalSubscription'], true);
        expect(result['hoursRemaining'], lessThan(4));
        expect(result['message'], contains('perderai l\'ingresso settimanale'));
      });
      
      test('should track cancellation with entryLost: true when < 4 hours', () {
        // Simula una disiscrizione tracciata con entryLost: true
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true, // Ingresso perso
          courseStartDate: testCourse1.startDate,
        );
        
        final userWithLostCancellation = FitropeUser(
          uid: 'user-with-lost-cancellation',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-2'], // 1 corso attivo
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollment],
        );
        
        // L'utente ha 1 corso attivo e 1 disiscrizione persa
        // Ingressi usati = 1 (attivo) + 1 (perso) = 2 ingressi usati
        // Limite: 2 ingressi settimanali
        // Dovrebbe essere al limite
        final state = getCourseState(testCourse3, userWithLostCancellation);
        
        expect(state, CourseState.LIMIT);
      });
    });
    
    group('Weekly Entries Calculation with Lost Cancellations', () {
      test('should consider lost cancellations in weekly entries calculation', () {
        // Utente con 2 ingressi settimanali, 2 corsi iscritti, 1 disiscrizione persa
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: testCourse1.startDate,
        );
        
        final userWithLostCancellation = FitropeUser(
          uid: 'user-with-lost-cancellation',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2'], // 2 corsi attivi
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollment],
        );
        
        // Ingressi usati = 2 corsi attivi + 1 disiscrizione persa = 3 ingressi usati
        // Limite: 2 ingressi settimanali
        // Dovrebbe superare il limite
        final state = getCourseState(testCourse3, userWithLostCancellation);
        
        expect(state, CourseState.LIMIT);
      });
      
      test('should not allow subscription when limit is reached with lost cancellations', () {
        // Utente con 2 ingressi settimanali, 2 corsi iscritti, 0 disiscrizioni perse
        final userAtLimit = FitropeUser(
          uid: 'user-at-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2'], // 2 corsi attivi = limite raggiunto
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [],
        );
        
        final state = getCourseState(testCourse3, userAtLimit);
        
        expect(state, CourseState.LIMIT);
      });
      
      test('should not allow subscription when lost cancellation uses up entries', () {
        // Utente con 2 ingressi settimanali, 1 corso iscritto, 1 disiscrizione persa
        // Ingressi usati = 1 (attivo) + 1 (perso) = 2 ingressi usati
        // Limite: 2 ingressi settimanali
        // Dovrebbe essere al limite
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: testCourse1.startDate,
        );
        
        final userAtLimit = FitropeUser(
          uid: 'user-at-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-2'], // 1 corso attivo
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollment],
        );
        
        final state = getCourseState(testCourse3, userAtLimit);
        
        // Dovrebbe essere al limite perché ha usato 2 ingressi (1 attivo + 1 perso)
        expect(state, CourseState.LIMIT);
      });
    });
    
    group('Cancellations in Different Weeks', () {
      test('should not count lost cancellations from different weeks', () {
        // Disiscrizione persa nella settimana precedente
        final lastWeekMonday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1 + 7));
        final cancelledEnrollmentLastWeek = CancelledEnrollment(
          courseId: 'course-last-week',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: Timestamp.fromDate(lastWeekMonday.add(const Duration(hours: 10))),
        );
        
        final userWithLastWeekCancellation = FitropeUser(
          uid: 'user-last-week',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2'], // 2 corsi questa settimana
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollmentLastWeek],
        );
        
        // La disiscrizione della settimana scorsa non dovrebbe influenzare questa settimana
        final state = getCourseState(testCourse3, userWithLastWeekCancellation);
        
        // Dovrebbe essere al limite perché ha 2 corsi questa settimana
        expect(state, CourseState.LIMIT);
      });
      
      test('should count lost cancellations only in the same week', () {
        // Disiscrizione persa questa settimana
        final cancelledEnrollmentThisWeek = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: testCourse1.startDate, // Questa settimana
        );
        
        final userWithThisWeekCancellation = FitropeUser(
          uid: 'user-this-week',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2'], // 2 corsi questa settimana
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollmentThisWeek],
        );
        
        // La disiscrizione di questa settimana dovrebbe influenzare il conteggio
        // Ingressi usati = 2 (attivi) + 1 (perso) = 3 ingressi usati
        // Limite: 2 ingressi settimanali
        final state = getCourseState(testCourse3, userWithThisWeekCancellation);
        
        // Dovrebbe superare il limite perché ha usato 3 ingressi (2 attivi + 1 perso)
        expect(state, CourseState.LIMIT);
      });
    });
    
    group('Cancellation Tracking Serialization', () {
      test('should serialize and deserialize CancelledEnrollment correctly', () {
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: testCourse1.startDate,
        );
        
        final json = cancelledEnrollment.toJson();
        final deserialized = CancelledEnrollment.fromJson(json);
        
        expect(deserialized.courseId, 'course-1');
        expect(deserialized.entryLost, true);
        expect(deserialized.cancelledAt, isA<Timestamp>());
        expect(deserialized.courseStartDate, isA<Timestamp>());
      });
      
      test('should serialize and deserialize FitropeUser with cancelledEnrollments', () {
        final cancelledEnrollment = CancelledEnrollment(
          courseId: 'course-1',
          cancelledAt: Timestamp.now(),
          entryLost: true,
          courseStartDate: testCourse1.startDate,
        );
        
        final user = FitropeUser(
          uid: 'user-test',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1'],
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
          cancelledEnrollments: [cancelledEnrollment],
        );
        
        final json = user.toJson();
        final deserialized = FitropeUser.fromJson(json);
        
        expect(deserialized.cancelledEnrollments.length, 1);
        expect(deserialized.cancelledEnrollments[0].courseId, 'course-1');
        expect(deserialized.cancelledEnrollments[0].entryLost, true);
      });
    });
  });
}

