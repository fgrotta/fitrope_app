import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Waitlist CourseState Tests', () {
    late Course fullCourse;
    late Course availableCourse;
    late FitropeUser eligibleUser;

    setUp(() {
      store.dispatch(SetAllCoursesAction([]));

      final now = DateTime.now();

      fullCourse = Course(
        id: 'course-full',
        uid: 'course-full',
        name: 'Corso Pieno',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
        capacity: 10,
        subscribed: 10,
        waitlist: [],
      );

      availableCourse = Course(
        id: 'course-available',
        uid: 'course-available',
        name: 'Corso Disponibile',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
        capacity: 10,
        subscribed: 5,
        waitlist: [],
      );

      eligibleUser = FitropeUser(
        uid: 'user-eligible',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      store.dispatch(SetAllCoursesAction([fullCourse, availableCourse]));
    });

    group('CAN_WAITLIST state', () {
      test('should return CAN_WAITLIST when course is full and user is eligible', () {
        final state = getCourseState(fullCourse, eligibleUser);
        expect(state, CourseState.CAN_WAITLIST);
      });

      test('should not return CAN_WAITLIST when course has spots', () {
        final state = getCourseState(availableCourse, eligibleUser);
        expect(state, isNot(CourseState.CAN_WAITLIST));
      });
    });

    group('IN_WAITLIST state', () {
      test('should return IN_WAITLIST when user is in waitlist and course is full', () {
        final courseWithUserInWaitlist = Course(
          id: 'course-full',
          uid: 'course-full',
          name: 'Corso Pieno',
          startDate: fullCourse.startDate,
          endDate: fullCourse.endDate,
          capacity: 10,
          subscribed: 10,
          waitlist: ['user-eligible'],
        );

        store.dispatch(SetAllCoursesAction([courseWithUserInWaitlist, availableCourse]));

        final state = getCourseState(courseWithUserInWaitlist, eligibleUser);
        expect(state, CourseState.IN_WAITLIST);
      });
    });

    group('WAITLIST_SPOT_AVAILABLE state', () {
      test('should return WAITLIST_SPOT_AVAILABLE when user is in waitlist and spot opens', () {
        // Corso con posti disponibili ma l'utente è ancora nella waitlist
        final courseWithSpotOpen = Course(
          id: 'course-spot-open',
          uid: 'course-spot-open',
          name: 'Corso Posto Libero',
          startDate: availableCourse.startDate,
          endDate: availableCourse.endDate,
          capacity: 10,
          subscribed: 9, // Non pieno
          waitlist: ['user-eligible'], // Utente ancora in waitlist
        );

        store.dispatch(SetAllCoursesAction([courseWithSpotOpen]));

        final state = getCourseState(courseWithSpotOpen, eligibleUser);
        expect(state, CourseState.WAITLIST_SPOT_AVAILABLE);
      });
    });

    group('Waitlist with subscription limits', () {
      test('should return CAN_WAITLIST when pacchetto entrate user has no entries but course is full (waitlist illimitata)', () {
        final userNoEntries = FitropeUser(
          uid: 'user-no-entries',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: 0,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          createdAt: DateTime.now(),
        );

        // La lista d'attesa è illimitata: l'assenza di crediti NON deve bloccarla.
        final state = getCourseState(fullCourse, userNoEntries);
        expect(state, CourseState.CAN_WAITLIST);
      });

      test('should return CAN_WAITLIST when pacchetto entrate user has entries and course is full', () {
        final userWithEntries = FitropeUser(
          uid: 'user-with-entries',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: 5,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          createdAt: DateTime.now(),
        );

        final state = getCourseState(fullCourse, userWithEntries);
        expect(state, CourseState.CAN_WAITLIST);
      });

      test('should return CAN_WAITLIST when weekly limit reached and course is full (waitlist illimitata)', () {
        final now = DateTime.now();
        // Crea 3 corsi nella stessa settimana futura
        final mondayNextWeek = now.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7));

        final course1 = Course(
          id: 'c1', uid: 'c1', name: 'Corso 1',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 11))),
          capacity: 20, subscribed: 5,
        );
        final course2 = Course(
          id: 'c2', uid: 'c2', name: 'Corso 2',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 1, hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 1, hours: 11))),
          capacity: 20, subscribed: 5,
        );
        final fullCourseNextWeek = Course(
          id: 'c-full', uid: 'c-full', name: 'Corso Pieno',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 2, hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 2, hours: 11))),
          capacity: 10, subscribed: 10,
        );

        store.dispatch(SetAllCoursesAction([course1, course2, fullCourseNextWeek]));

        final userAtLimit = FitropeUser(
          uid: 'user-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['c1', 'c2'], // 2 corsi = limite raggiunto
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
          role: 'User',
          createdAt: now,
        );

        // La lista d'attesa è illimitata: il limite settimanale raggiunto NON deve bloccarla.
        final state = getCourseState(fullCourseNextWeek, userAtLimit);
        expect(state, CourseState.CAN_WAITLIST);
      });
    });

    group('Waitlist ignora limiti settimanali/crediti', () {
      test('corso CON POSTI + limite settimanale raggiunto -> LIMIT (la sottoscrizione diretta resta bloccata)', () {
        final now = DateTime.now();
        final mondayNextWeek =
            now.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7));

        final course1 = Course(
          id: 'c1', uid: 'c1', name: 'Corso 1',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(hours: 11))),
          capacity: 20, subscribed: 5,
        );
        final course2 = Course(
          id: 'c2', uid: 'c2', name: 'Corso 2',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 1, hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 1, hours: 11))),
          capacity: 20, subscribed: 5,
        );
        // Corso con posti disponibili (subscribed < capacity)
        final availableCourseNextWeek = Course(
          id: 'c-available', uid: 'c-available', name: 'Corso Disponibile',
          startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 2, hours: 10))),
          endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 2, hours: 11))),
          capacity: 10, subscribed: 3,
        );

        store.dispatch(SetAllCoursesAction([course1, course2, availableCourseNextWeek]));

        final userAtLimit = FitropeUser(
          uid: 'user-limit',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['c1', 'c2'], // 2 corsi = limite raggiunto
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateSettimanali: 2,
          fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
          role: 'User',
          createdAt: now,
        );

        final state = getCourseState(availableCourseNextWeek, userAtLimit);
        expect(state, CourseState.LIMIT);
      });

      test('corso CON POSTI + pacchetto entrate senza crediti -> SUBSCRIBE_LIMIT (la sottoscrizione diretta resta bloccata)', () {
        final now = DateTime.now();
        final availableCourse = Course(
          id: 'c-available', uid: 'c-available', name: 'Corso Disponibile',
          startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
          endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
          capacity: 10, subscribed: 3,
        );

        store.dispatch(SetAllCoursesAction([availableCourse]));

        final userNoEntries = FitropeUser(
          uid: 'user-no-entries',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
          entrateDisponibili: 0,
          role: 'User',
          createdAt: now,
        );

        final state = getCourseState(availableCourse, userNoEntries);
        expect(state, CourseState.SUBSCRIBE_LIMIT);
      });

      test('corso pieno + tipologiaIscrizione non valida -> NULL (la waitlist resta gated dall\'idoneità)', () {
        final now = DateTime.now();
        final fullCourseNoType = Course(
          id: 'c-notype', uid: 'c-notype', name: 'Corso Pieno',
          startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
          endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
          capacity: 10, subscribed: 10,
        );

        store.dispatch(SetAllCoursesAction([fullCourseNoType]));

        final userNoType = FitropeUser(
          uid: 'user-no-type',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          tipologiaIscrizione: null,
          role: 'User',
          createdAt: now,
        );

        // La lista d'attesa è illimitata sui limiti settimanali/crediti, ma un
        // utente senza abbonamento valido (NULL) resta comunque non idoneo.
        final state = getCourseState(fullCourseNoType, userNoType);
        expect(state, CourseState.NULL);
      });
    });

    group('SUBSCRIBED takes priority over waitlist', () {
      test('should return SUBSCRIBED even if user is also in waitlist', () {
        final courseSubscribedAndWaitlist = Course(
          id: 'course-both',
          uid: 'course-both',
          name: 'Corso',
          startDate: availableCourse.startDate,
          endDate: availableCourse.endDate,
          capacity: 10,
          subscribed: 5,
          waitlist: ['user-subscribed'],
        );

        final userSubscribed = FitropeUser(
          uid: 'user-subscribed',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: ['course-both'], // Iscritto
          tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
          entrateSettimanali: 3,
          fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          createdAt: DateTime.now(),
        );

        store.dispatch(SetAllCoursesAction([courseSubscribedAndWaitlist]));

        final state = getCourseState(courseSubscribedAndWaitlist, userSubscribed);
        expect(state, CourseState.SUBSCRIBED);
      });
    });
  });

  group('Waitlist Serialization Tests', () {
    group('Course waitlist', () {
      test('should serialize waitlist in Course.toJson', () {
        final course = Course(
          id: 'c1',
          uid: 'c1',
          name: 'Corso',
          startDate: Timestamp.fromDate(DateTime.now()),
          endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
          capacity: 10,
          subscribed: 10,
          waitlist: ['user-1', 'user-2'],
        );

        final json = course.toJson();
        expect(json['waitlist'], ['user-1', 'user-2']);
      });

      test('should deserialize waitlist in Course.fromJson', () {
        final json = {
          'uid': 'c1',
          'name': 'Corso',
          'startDate': Timestamp.fromDate(DateTime.now()),
          'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
          'capacity': 10,
          'subscribed': 10,
          'waitlist': ['user-1', 'user-2'],
        };

        final course = Course.fromJson(json);
        expect(course.waitlist, ['user-1', 'user-2']);
      });

      test('should default to empty list when waitlist is missing', () {
        final json = {
          'uid': 'c1',
          'name': 'Corso',
          'startDate': Timestamp.fromDate(DateTime.now()),
          'endDate': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
          'capacity': 10,
          'subscribed': 5,
        };

        final course = Course.fromJson(json);
        expect(course.waitlist, isEmpty);
      });
    });

    group('User waitlistCourses', () {
      test('should serialize waitlistCourses in FitropeUser.toJson', () {
        final user = FitropeUser(
          uid: 'u1',
          email: 'test@example.com',
          name: 'Test',
          lastName: 'User',
          courses: [],
          role: 'User',
          createdAt: DateTime.now(),
          waitlistCourses: ['c1', 'c2'],
        );

        final json = user.toJson();
        expect(json['waitlistCourses'], ['c1', 'c2']);
      });

      test('should deserialize waitlistCourses in FitropeUser.fromJson', () {
        final json = {
          'uid': 'u1',
          'email': 'test@example.com',
          'name': 'Test',
          'lastName': 'User',
          'courses': <String>[],
          'role': 'User',
          'createdAt': Timestamp.fromDate(DateTime.now()),
          'waitlistCourses': ['c1', 'c2'],
        };

        final user = FitropeUser.fromJson(json);
        expect(user.waitlistCourses, ['c1', 'c2']);
      });

      test('should default to empty list when waitlistCourses is missing (legacy users)', () {
        final json = {
          'uid': 'u1',
          'email': 'test@example.com',
          'name': 'Test',
          'lastName': 'User',
          'courses': <String>[],
          'role': 'User',
          'createdAt': Timestamp.fromDate(DateTime.now()),
        };

        final user = FitropeUser.fromJson(json);
        expect(user.waitlistCourses, isEmpty);
      });
    });
  });

  group('getCourseState null entrateSettimanali Tests', () {
    setUp(() {
      store.dispatch(SetAllCoursesAction([]));
    });

    test('should allow subscription when entrateSettimanali is null (no weekly limit)', () {
      final now = DateTime.now();
      final course = Course(
        id: 'c1',
        uid: 'c1',
        name: 'Corso',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
        capacity: 20,
        subscribed: 5,
      );

      store.dispatch(SetAllCoursesAction([course]));

      final user = FitropeUser(
        uid: 'user-no-limit',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: null,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      final state = getCourseState(course, user);
      expect(state, CourseState.CAN_SUBSCRIBE);
    });

    test('should return CAN_WAITLIST when entrateSettimanali is null and course is full', () {
      final now = DateTime.now();
      final course = Course(
        id: 'c1',
        uid: 'c1',
        name: 'Corso Pieno',
        startDate: Timestamp.fromDate(now.add(const Duration(days: 3))),
        endDate: Timestamp.fromDate(now.add(const Duration(days: 3, hours: 1))),
        capacity: 10,
        subscribed: 10,
      );

      store.dispatch(SetAllCoursesAction([course]));

      final user = FitropeUser(
        uid: 'user-no-limit',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateSettimanali: null,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 30))),
        role: 'User',
        createdAt: now,
      );

      final state = getCourseState(course, user);
      expect(state, CourseState.CAN_WAITLIST);
    });

    test('should not crash with null entrateSettimanali and many subscribed courses', () {
      final now = DateTime.now();
      final mondayNextWeek = now.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7));

      final courses = List.generate(5, (i) => Course(
        id: 'c$i', uid: 'c$i', name: 'Corso $i',
        startDate: Timestamp.fromDate(mondayNextWeek.add(Duration(days: i, hours: 10))),
        endDate: Timestamp.fromDate(mondayNextWeek.add(Duration(days: i, hours: 11))),
        capacity: 20, subscribed: 5,
      ));

      final newCourse = Course(
        id: 'c-new', uid: 'c-new', name: 'Nuovo Corso',
        startDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 5, hours: 10))),
        endDate: Timestamp.fromDate(mondayNextWeek.add(const Duration(days: 5, hours: 11))),
        capacity: 20, subscribed: 5,
      );

      store.dispatch(SetAllCoursesAction([...courses, newCourse]));

      final user = FitropeUser(
        uid: 'user-many-courses',
        email: 'test@example.com',
        name: 'Test',
        lastName: 'User',
        courses: courses.map((c) => c.uid).toList(),
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_ANNUALE,
        entrateSettimanali: null,
        fineIscrizione: Timestamp.fromDate(now.add(const Duration(days: 365))),
        role: 'User',
        createdAt: now,
      );

      // Non deve crashare con Null check operator
      final state = getCourseState(newCourse, user);
      expect(state, CourseState.CAN_SUBSCRIBE);
    });
  });
}
