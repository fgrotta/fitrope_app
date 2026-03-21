import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/reducers.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

AppState _initialState() => AppState(
      user: null,
      isLoading: false,
      allCourses: [],
    );

FitropeUser _testUser() => FitropeUser(
      uid: 'u1',
      email: 'test@test.com',
      name: 'Mario',
      lastName: 'Rossi',
      courses: [],
      role: 'User',
      createdAt: DateTime(2024, 1, 1),
    );

Course _testCourse() => Course(
      id: 'c1',
      uid: 'c1',
      name: 'Yoga',
      startDate: Timestamp.fromDate(DateTime(2024, 6, 1, 10, 0)),
      endDate: Timestamp.fromDate(DateTime(2024, 6, 1, 11, 0)),
      capacity: 10,
      subscribed: 0,
    );

void main() {
  group('appReducer', () {
    test('returns unchanged state for unknown action', () {
      final state = _initialState();
      final next = appReducer(state, Object());
      expect(next.user, isNull);
      expect(next.isLoading, false);
      expect(next.allCourses, isEmpty);
    });

    group('SetUserAction', () {
      test('sets user in state', () {
        final user = _testUser();
        final next = appReducer(_initialState(), SetUserAction(user));
        expect(next.user, same(user));
      });

      test('can set user to null', () {
        final state = AppState(user: _testUser(), isLoading: false, allCourses: []);
        final next = appReducer(state, SetUserAction(null));
        expect(next.user, isNull);
      });

      test('preserves other state fields', () {
        final course = _testCourse();
        final state = AppState(user: null, isLoading: true, allCourses: [course]);
        final next = appReducer(state, SetUserAction(_testUser()));
        expect(next.isLoading, true);
        expect(next.allCourses, [course]);
      });
    });

    group('StartLoadingAction', () {
      test('sets isLoading to true', () {
        final next = appReducer(_initialState(), StartLoadingAction());
        expect(next.isLoading, true);
      });

      test('preserves user and allCourses', () {
        final user = _testUser();
        final course = _testCourse();
        final state = AppState(user: user, isLoading: false, allCourses: [course]);
        final next = appReducer(state, StartLoadingAction());
        expect(next.user, same(user));
        expect(next.allCourses, [course]);
      });
    });

    group('FinishLoadingAction', () {
      test('sets isLoading to false', () {
        final state = AppState(user: null, isLoading: true, allCourses: []);
        final next = appReducer(state, FinishLoadingAction());
        expect(next.isLoading, false);
      });

      test('preserves user and allCourses', () {
        final user = _testUser();
        final course = _testCourse();
        final state = AppState(user: user, isLoading: true, allCourses: [course]);
        final next = appReducer(state, FinishLoadingAction());
        expect(next.user, same(user));
        expect(next.allCourses, [course]);
      });
    });

    group('SetAllCoursesAction', () {
      test('sets allCourses in state', () {
        final courses = [_testCourse()];
        final next = appReducer(_initialState(), SetAllCoursesAction(courses));
        expect(next.allCourses, courses);
      });

      test('replaces existing allCourses', () {
        final old = _testCourse();
        final newCourse = Course(
          id: 'c2', uid: 'c2', name: 'Pilates',
          startDate: Timestamp.fromDate(DateTime(2024, 6, 2, 10, 0)),
          endDate: Timestamp.fromDate(DateTime(2024, 6, 2, 11, 0)),
          capacity: 8, subscribed: 0,
        );
        final state = AppState(user: null, isLoading: false, allCourses: [old]);
        final next = appReducer(state, SetAllCoursesAction([newCourse]));
        expect(next.allCourses, [newCourse]);
        expect(next.allCourses, isNot(contains(old)));
      });

      test('can set empty courses list', () {
        final state = AppState(user: null, isLoading: false, allCourses: [_testCourse()]);
        final next = appReducer(state, SetAllCoursesAction([]));
        expect(next.allCourses, isEmpty);
      });

      test('preserves user and isLoading', () {
        final user = _testUser();
        final state = AppState(user: user, isLoading: true, allCourses: []);
        final next = appReducer(state, SetAllCoursesAction([_testCourse()]));
        expect(next.user, same(user));
        expect(next.isLoading, true);
      });
    });
  });
}
