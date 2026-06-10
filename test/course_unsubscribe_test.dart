import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/userSubscription.dart';
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
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 8, seconds: 30))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 9, seconds: 30))),
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
        courses: ['test-course-1', 'test-course-soon', 'test-course-exact', 'test-course-past', 'test-course-almost-8', 'test-course-just-over-8'],
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
          startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 8, minutes: 5))),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 9, minutes: 5))),
          capacity: 20,
          subscribed: 5,
        );

        final result = CourseUnsubscribeHelper.canUnsubscribe(courseJustOver8, testUserPacchetto);

        expect(result['requiresConfirmation'], false);
        expect(result['hoursRemaining'], 8);
      });
    });
  });

  group('canUnsubscribe — modello multi-abbonamento', () {
    Course courseInHours(double hours, {List<String> tags = const []}) {
      final minutes = (hours * 60).round();
      return Course(
        id: 'c-multi',
        uid: 'c-multi',
        name: 'Corso Multi',
        startDate:
            Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes))),
        endDate: Timestamp.fromDate(
            DateTime.now().add(Duration(minutes: minutes + 60))),
        capacity: 20,
        subscribed: 5,
        tags: tags,
      );
    }

    UserSubscription sub({
      required BillingMode billingMode,
      Set<String> courseTypeTags = const {'Open'},
      DateTime? endDate,
    }) {
      return UserSubscription(
        id: 'sub-1',
        planKey: 'test-plan',
        family: SubscriptionFamily.OPEN,
        billingMode: billingMode,
        courseTypeTags: courseTypeTags,
        weeklyFrequency: billingMode == BillingMode.FREQUENCY ? 2 : null,
        remainingEntries: billingMode == BillingMode.ENTRIES ? 5 : null,
        startDate: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 10))),
        endDate: Timestamp.fromDate(
            endDate ?? DateTime.now().add(const Duration(days: 30))),
      );
    }

    FitropeUser userWith(List<UserSubscription> subs) {
      return FitropeUser(
        uid: 'user-multi',
        email: 'multi@example.com',
        name: 'Multi',
        lastName: 'Sub',
        courses: ['c-multi'],
        // Campi legacy volutamente "fuorvianti": col nuovo modello NON devono
        // determinare la finestra.
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 5,
        role: 'User',
        createdAt: DateTime.now(),
        activeSubscriptions: subs,
      );
    }

    test('abbonamento ENTRIES: finestra 8h (conferma entro, rimborso oltre)', () {
      final user = userWith([sub(billingMode: BillingMode.ENTRIES)]);

      final outside = CourseUnsubscribeHelper.canUnsubscribe(
          courseInHours(10), user);
      expect(outside['requiresConfirmation'], false);
      expect(outside['isPacchettoEntrate'], true);
      expect(outside['message'], 'Disiscrizione: il credito ti sarà rimborsato');

      final within =
          CourseUnsubscribeHelper.canUnsubscribe(courseInHours(6), user);
      expect(within['requiresConfirmation'], true);
      expect(within['message'],
          'Disiscrizione a meno di 8 ore: perderai il credito');
    });

    test('abbonamento FREQUENCY: finestra 4h (non 8h)', () {
      final user = userWith([sub(billingMode: BillingMode.FREQUENCY)]);

      // A 6h: entro la finestra legacy del pacchetto (8h) ma fuori da quella
      // FREQUENCY (4h) → nessuna conferma (i campi legacy sono ignorati).
      final at6h =
          CourseUnsubscribeHelper.canUnsubscribe(courseInHours(6), user);
      expect(at6h['requiresConfirmation'], false);
      expect(at6h['isPacchettoEntrate'], false);

      final at2h =
          CourseUnsubscribeHelper.canUnsubscribe(courseInHours(2), user);
      expect(at2h['requiresConfirmation'], true);
      expect(at2h['isTemporalSubscription'], true);
      expect(at2h['message'],
          'Disiscrizione a meno di 4 ore: perderai l\'ingresso settimanale');
    });

    test('nessun abbonamento copre la tipologia: nessuna finestra', () {
      final user = userWith([
        sub(billingMode: BillingMode.ENTRIES, courseTypeTags: {'Hyrox'}),
      ]);

      final result = CourseUnsubscribeHelper.canUnsubscribe(
          courseInHours(2), user); // corso Open, copre solo Hyrox
      expect(result['requiresConfirmation'], false);
      expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
    });

    test('abbonamento vivo ma scaduto alla DATA DEL CORSO: nessuna finestra', () {
      final user = userWith([
        sub(
          billingMode: BillingMode.ENTRIES,
          // Vivo adesso, ma termina prima dell'inizio del corso (tra 2h).
          endDate: DateTime.now().add(const Duration(hours: 1)),
        ),
      ]);

      final result =
          CourseUnsubscribeHelper.canUnsubscribe(courseInHours(2), user);
      expect(result['requiresConfirmation'], false);
      expect(result['message'], 'Disiscrizione: liberi il posto nel corso');
    });

    test('snapshot con SOLE voci scadute: torna al modello legacy (finestra 8h)', () {
      // La voce scaduta non seleziona più il modello multi-abbonamento: valgono
      // i campi legacy (PACCHETTO_ENTRATE → conferma entro 8h), come sul server.
      final user = userWith([
        sub(
          billingMode: BillingMode.ENTRIES,
          endDate: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ]);

      final result =
          CourseUnsubscribeHelper.canUnsubscribe(courseInHours(2), user);
      expect(result['requiresConfirmation'], true);
      expect(result['isPacchettoEntrate'], true);
      expect(result['message'],
          'Disiscrizione a meno di 8 ore: perderai il credito');
    });
  });
}
