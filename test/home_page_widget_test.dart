import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/pages/protected/home_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Course homeCourse(String uid, DateTime start) => Course(
      id: uid, // ignore: deprecated_member_use_from_same_package
      uid: uid,
      name: 'Corso $uid',
      startDate: Timestamp.fromDate(start),
      endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
      capacity: 10,
      subscribed: 0,
      tags: const ['Open'],
    );

FitropeUser homeUser({
  List<String> courses = const [],
  List<String> waitlist = const [],
  List<UserSubscription> subscriptions = const [],
  Timestamp? certificate,
}) =>
    FitropeUser(
      uid: 'member',
      email: 'member@example.com',
      name: 'Mario',
      lastName: 'Rossi',
      courses: courses,
      waitlistCourses: waitlist,
      role: 'User',
      createdAt: DateTime(2026),
      activeSubscriptions: subscriptions,
      certificatoScadenza: certificate,
      tipologiaCorsoTags: const ['Open'],
    );

Future<void> pumpHome(
  WidgetTester tester,
  FitropeUser user,
  List<Course> courses,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  store.dispatch(SetUserAction(user));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(900, 1100)),
          child: HomePage(
            loadCourses: () async => courses,
            loadTrainers: () async => [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initItalianTime);

  testWidgets('renderizza subscription, corsi futuri e waitlist',
      (tester) async {
    final now = DateTime.now();
    final subscription = UserSubscription(
      id: 'sub-open',
      planKey: 'open_3x_3m',
      family: SubscriptionFamily.OPEN,
      billingMode: BillingMode.FREQUENCY,
      courseTypeTags: const {'Open'},
      weeklyFrequency: 3,
      startDate: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      endDate: Timestamp.fromDate(now.add(const Duration(days: 30))),
    );
    final courses = [
      homeCourse('booked', now.add(const Duration(days: 2))),
      homeCourse('waiting', now.add(const Duration(days: 3))),
    ];
    await pumpHome(
      tester,
      homeUser(
        courses: const ['booked'],
        waitlist: const ['waiting'],
        subscriptions: [subscription],
      ),
      courses,
    );

    expect(find.byKey(const Key('home-subscriptions-heading')), findsOneWidget);
    expect(find.byKey(const Key('course-card-booked')), findsOneWidget);
    expect(find.byKey(const Key('home-waitlist-section')), findsOneWidget);
    expect(find.byKey(const Key('course-card-waiting')), findsOneWidget);
  });

  testWidgets('mostra empty state e certificato entro tre giorni',
      (tester) async {
    await pumpHome(
      tester,
      homeUser(
        certificate: Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 2)),
        ),
      ),
      [],
    );
    expect(find.text('Nessun abbonamento disponibile'), findsOneWidget);
    expect(find.text('Nessun corso disponibile'), findsOneWidget);
    expect(find.byKey(const Key('home-waitlist-section')), findsNothing);
    expect(find.byKey(const Key('home-certificate-expiry')), findsOneWidget);
  });
}
