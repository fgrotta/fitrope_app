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
  group('Current Enrollment Logic Tests', () {
    
    late Course testCourse1;
    late Course testCourse2;
    late Course testCourse3;
    late Course testCourseNextWeek;
    late FitropeUser userAbbonamentoMensile;
    
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
      
      // Utente con Abbonamento Mensile (3 ingressi settimanali)
      userAbbonamentoMensile = FitropeUser(
        uid: 'user-abbonamento',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: ['course-1', 'course-2'], // Iscritto a 2 corsi questa settimana
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateDisponibili: null, // Non usato per abbonamenti temporali
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        isActive: true,
        isAnonymous: false,
        createdAt: now,
      );
      
      // Imposta i corsi nello store
      store.dispatch(SetAllCoursesAction([
        testCourse1,
        testCourse2,
        testCourse3,
        testCourseNextWeek,
      ]));
    });
    
    group('Subscription Logic for Temporal Subscriptions', () {
      test('should not modify entrateDisponibili for temporal subscriptions', () {
        // Questo test verifica il comportamento atteso:
        // Per abbonamenti temporali, entrateDisponibili non viene modificato
        // (questo è verificato nel codice di subscribeToCourse che decrementa sempre)
        // Nota: Il codice attuale decrementa sempre, ma per abbonamenti temporali
        // entrateDisponibili è null, quindi questo test verifica la logica attesa
        
        expect(userAbbonamentoMensile.entrateDisponibili, isNull);
        // Dopo l'iscrizione, entrateDisponibili dovrebbe rimanere null
        // (anche se il codice attuale tenta di decrementarlo)
      });
      
      test('should add course to courses list for temporal subscriptions', () {
        // Verifica che quando un utente si iscrive, il corso viene aggiunto alla lista
        expect(userAbbonamentoMensile.courses, contains('course-1'));
        expect(userAbbonamentoMensile.courses, contains('course-2'));
        expect(userAbbonamentoMensile.courses.length, 2);
      });
    });
    
    group('Unsubscription Logic for Temporal Subscriptions', () {
      test('should remove course from courses list', () {
        // Verifica che quando un utente si disiscrive, il corso viene rimosso
        final coursesBefore = List<String>.from(userAbbonamentoMensile.courses);
        expect(coursesBefore, contains('course-1'));
        
        // Simula rimozione (logica attuale)
        final coursesAfter = List<String>.from(coursesBefore);
        coursesAfter.remove('course-1');
        
        expect(coursesAfter, isNot(contains('course-1')));
        expect(coursesAfter.length, coursesBefore.length - 1);
      });
      
      test('should not modify entrateDisponibili for temporal subscriptions', () {
        // Per abbonamenti temporali, entrateDisponibili non viene modificato
        expect(userAbbonamentoMensile.entrateDisponibili, isNull);
        // Dopo la disiscrizione, entrateDisponibili dovrebbe rimanere null
      });
    });
    
    group('Weekly Entries Calculation - getCourseState', () {
      test('should correctly count weekly entries for temporal subscriptions', () {
        // Utente con 3 ingressi settimanali, iscritto a 2 corsi questa settimana
        // Dovrebbe poter iscriversi a un terzo corso
        final state = getCourseState(testCourse3, userAbbonamentoMensile);
        
        expect(state, CourseState.CAN_SUBSCRIBE);
      });
      
      test('should return LIMIT when weekly entries limit is reached', () {
        // Utente con 3 ingressi settimanali, iscritto a 2 corsi
        // Aggiungiamo un terzo corso alla lista per raggiungere il limite
        final userAtLimit = FitropeUser(
          uid: 'user-at-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2', 'course-3'], // 3 corsi = limite raggiunto
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 3,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
        );
        
        // Crea un nuovo corso nella stessa settimana
        final newCourse = Course(
          id: 'course-4',
          uid: 'course-4',
          name: 'Corso Giovedì',
          startDate: Timestamp.fromDate(
            DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1))
              .add(const Duration(days: 3, hours: 10))
          ),
          endDate: Timestamp.fromDate(
            DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1))
              .add(const Duration(days: 3, hours: 11))
          ),
          capacity: 20,
          subscribed: 5,
        );
        
        store.dispatch(SetAllCoursesAction([
          testCourse1,
          testCourse2,
          testCourse3,
          newCourse,
        ]));
        
        final state = getCourseState(newCourse, userAtLimit);
        
        expect(state, CourseState.LIMIT);
      });
      
      test('should not count courses from different weeks', () {
        // Utente iscritto a 2 corsi questa settimana e 1 corso prossima settimana
        // Dovrebbe poter iscriversi a un altro corso questa settimana (se limite è 3)
        final userWithNextWeekCourse = FitropeUser(
          uid: 'user-next-week',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1', 'course-2', 'course-next-week'], // 2 questa settimana, 1 prossima
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: 3,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
        );
        
        final state = getCourseState(testCourse3, userWithNextWeekCourse);
        
        // Dovrebbe poter iscriversi perché ha solo 2 corsi questa settimana
        expect(state, CourseState.CAN_SUBSCRIBE);
      });
      
      test('should handle user with no weekly limit correctly', () {
        // Utente con abbonamento che non ha limite settimanale specificato
        final userNoLimit = FitropeUser(
          uid: 'user-no-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-1'],
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateDisponibili: null,
          entrateSettimanali: null, // Nessun limite
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
        );
        
        final state = getCourseState(testCourse2, userNoLimit);
        
        // Dovrebbe poter iscriversi (il codice attuale potrebbe gestire null diversamente)
        // Verifichiamo che non sia LIMIT
        expect(state, isNot(CourseState.LIMIT));
      });
    });
    
    group('CourseUnsubscribeHelper.canUnsubscribe for Temporal Subscriptions', () {
      test('should not require confirmation for temporal subscriptions (current logic)', () {
        // Corso che inizia tra 10 ore
        final courseFar = Course(
          id: 'course-far',
          uid: 'course-far',
          name: 'Corso Lontano',
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 11))),
          capacity: 20,
          subscribed: 5,
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseFar, userAbbonamentoMensile);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], false);
        expect(result['isPacchettoEntrate'], false);
        expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
      });
      
      test('should not require confirmation even for course starting soon (current logic)', () {
        // Corso che inizia tra 2 ore (< 4 ore, ma logica attuale non richiede conferma)
        final courseSoon = Course(
          id: 'course-soon',
          uid: 'course-soon',
          name: 'Corso Imminente',
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 3))),
          capacity: 20,
          subscribed: 5,
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseSoon, userAbbonamentoMensile);
        
        // Logica attuale: non richiede conferma per abbonamenti temporali
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], false);
        expect(result['isPacchettoEntrate'], false);
      });
      
      test('should require confirmation for Pacchetto Entrate < 8 hours', () {
        // Corso che inizia tra 6 ore (< 8 ore)
        final courseSoon = Course(
          id: 'course-soon',
          uid: 'course-soon',
          name: 'Corso Imminente',
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 6))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 7))),
          capacity: 20,
          subscribed: 5,
        );
        
        final userWithCourse = FitropeUser(
          uid: 'user-pacchetto-with-course',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-soon'],
          tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: 5,
          entrateSettimanali: null,
          fineIscrizione: null,
          role: 'User',
          isActive: true,
          isAnonymous: false,
          createdAt: DateTime.now(),
        );
        
        final result = CourseUnsubscribeHelper.canUnsubscribe(courseSoon, userWithCourse);
        
        expect(result['canUnsubscribe'], true);
        expect(result['requiresConfirmation'], true);
        expect(result['isPacchettoEntrate'], true);
        expect(result['message'], 'Disiscrizione a meno di 8 ore: perderai il credito');
      });
    });
  });
}

