import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/api/courses/leaveWaitlist.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Test per la logica di validazione delle operazioni waitlist.
/// Questi test coprono le regole di business che getCourseState applica
/// per decidere se un utente può/non può unirsi alla waitlist.
void main() {
  group('Waitlist Join Validation Logic', () {
    late FitropeUser normalUser;
    final now = DateTime.now();

    setUp(() {
      store.dispatch(SetAllCoursesAction([]));

      normalUser = FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Mario',
        lastName: 'Rossi',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );
    });

    test('utente non può entrare in waitlist se corso non è pieno', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 5,
      );
      store.dispatch(SetAllCoursesAction([course]));

      final state = getCourseState(course, normalUser);
      expect(state, CourseState.CAN_SUBSCRIBE);
      expect(state, isNot(CourseState.CAN_WAITLIST));
    });

    test('utente può entrare in waitlist se corso è pieno e ha crediti', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
      );
      store.dispatch(SetAllCoursesAction([course]));

      final state = getCourseState(course, normalUser);
      expect(state, CourseState.CAN_WAITLIST);
    });

    test('utente con abbonamento scaduto non può entrare in waitlist', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 60))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 60, hours: 1))),
        capacity: 10, subscribed: 10,
      );
      store.dispatch(SetAllCoursesAction([course]));

      final expiredUser = FitropeUser(
        uid: 'user-expired',
        email: 'test@example.com',
        name: 'Test', lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 5))),
        role: 'User',
        createdAt: now,
      );

      final state = getCourseState(course, expiredUser);
      expect(state, CourseState.EXPIRED);
    });

    test('utente pacchetto entrate senza crediti PUÒ entrare in waitlist (lista d\'attesa illimitata)', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
      );
      store.dispatch(SetAllCoursesAction([course]));

      final userNoEntries = FitropeUser(
        uid: 'user-no-entries',
        email: 'test@example.com',
        name: 'Test', lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 0,
        role: 'User',
        createdAt: now,
      );

      // La lista d'attesa è illimitata: l'assenza di crediti NON deve bloccarla.
      final state = getCourseState(course, userNoEntries);
      expect(state, CourseState.CAN_WAITLIST);
    });

    test('utente già in waitlist vede IN_WAITLIST', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: ['user-1'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final state = getCourseState(course, normalUser);
      expect(state, CourseState.IN_WAITLIST);
    });

    test('utente in waitlist vede WAITLIST_SPOT_AVAILABLE quando si libera un posto', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 9,
        waitlist: ['user-1'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final state = getCourseState(course, normalUser);
      expect(state, CourseState.WAITLIST_SPOT_AVAILABLE);
    });

    test('utente iscritto al corso vede SUBSCRIBED anche se in waitlist', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: ['user-1'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final subscribedUser = FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Test', lastName: 'User',
        courses: ['c1'],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      final state = getCourseState(course, subscribedUser);
      expect(state, CourseState.SUBSCRIBED);
    });

    test('corso passato mostra CLOSED indipendentemente dalla waitlist', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso Passato',
        startDate: Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
        endDate: Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: ['user-1'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final state = getCourseState(course, normalUser);
      expect(state, CourseState.CLOSED);
    });
  });

  group('Waitlist Leave Validation Logic', () {
    final now = DateTime.now();

    test('utente non in waitlist non dovrebbe poter lasciare', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: ['other-user'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final user = FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Test', lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      // Utente non in waitlist -> stato CAN_WAITLIST, non IN_WAITLIST
      final state = getCourseState(course, user);
      expect(state, CourseState.CAN_WAITLIST);
      expect(state, isNot(CourseState.IN_WAITLIST));
    });
  });

  group('Waitlist Data Consistency', () {
    final now = DateTime.now();

    test('waitlistCourses e course.waitlist devono essere coerenti per getCourseState', () {
      // Scenario: utente ha courseId in waitlistCourses ma course.waitlist non contiene userId
      // getCourseState usa solo course.waitlist, non user.waitlistCourses
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: [], // Utente NON in waitlist del corso
      );
      store.dispatch(SetAllCoursesAction([course]));

      final user = FitropeUser(
        uid: 'user-1',
        email: 'test@example.com',
        name: 'Test', lastName: 'User',
        courses: [],
        waitlistCourses: ['c1'], // Ma ha il corso nella sua lista waitlist
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      // getCourseState dipende da course.waitlist, non da user.waitlistCourses
      final state = getCourseState(course, user);
      expect(state, CourseState.CAN_WAITLIST); // Non IN_WAITLIST
    });

    test('waitlist multipla: più utenti in waitlist stesso corso', () {
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 10,
        waitlist: ['user-1', 'user-2', 'user-3'],
      );
      store.dispatch(SetAllCoursesAction([course]));

      final user1 = FitropeUser(
        uid: 'user-1', email: 'a@b.com', name: 'A', lastName: 'B',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User', createdAt: now,
      );

      final user4 = FitropeUser(
        uid: 'user-4', email: 'c@d.com', name: 'C', lastName: 'D',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User', createdAt: now,
      );

      expect(getCourseState(course, user1), CourseState.IN_WAITLIST);
      expect(getCourseState(course, user4), CourseState.CAN_WAITLIST);
    });

    test('subscribeToCourse deve pulire waitlist: scenario coperto da getCourseState', () {
      // Dopo che un utente in waitlist si iscrive, il suo stato diventa SUBSCRIBED
      final course = Course(
        id: 'c1', uid: 'c1', name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 2))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 2, hours: 1))),
        capacity: 10, subscribed: 9,
        waitlist: [], // Già rimosso dalla waitlist da subscribeToCourse
      );
      store.dispatch(SetAllCoursesAction([course]));

      final user = FitropeUser(
        uid: 'user-1', email: 'a@b.com', name: 'A', lastName: 'B',
        courses: ['c1'], // Iscritto
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User', createdAt: now,
      );

      final state = getCourseState(course, user);
      expect(state, CourseState.SUBSCRIBED);
    });

    test('leaveWaitlist pulisce anche utenti visibili solo da waitlistCourses', () {
      final result = computeWaitlistRemoval(
        courseWaitlist: const [],
        userWaitlistCourses: const ['c1', 'c2'],
        userId: 'user-1',
        courseId: 'c1',
      );

      expect(result.removedFromCourse, false);
      expect(result.removedFromUser, true);
      expect(result.hasChanges, true);
      expect(result.updatedCourseWaitlist, isEmpty);
      expect(result.updatedUserWaitlistCourses, ['c2']);
    });

    test('leaveWaitlist continua a rimuovere entrambi i lati quando coerenti', () {
      final result = computeWaitlistRemoval(
        courseWaitlist: const ['user-1', 'user-2'],
        userWaitlistCourses: const ['c1', 'c3'],
        userId: 'user-1',
        courseId: 'c1',
      );

      expect(result.removedFromCourse, true);
      expect(result.removedFromUser, true);
      expect(result.hasChanges, true);
      expect(result.updatedCourseWaitlist, ['user-2']);
      expect(result.updatedUserWaitlistCourses, ['c3']);
    });

    test('leaveWaitlist resta errore se utente e corso non hanno alcun legame waitlist', () {
      final result = computeWaitlistRemoval(
        courseWaitlist: const ['user-2'],
        userWaitlistCourses: const ['c3'],
        userId: 'user-1',
        courseId: 'c1',
      );

      expect(result.removedFromCourse, false);
      expect(result.removedFromUser, false);
      expect(result.hasChanges, false);
      expect(result.updatedCourseWaitlist, ['user-2']);
      expect(result.updatedUserWaitlistCourses, ['c3']);
    });
  });
}
