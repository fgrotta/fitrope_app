import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser subscriber(String uid, {bool active = true}) => FitropeUser(
      uid: uid,
      email: '$uid@example.com',
      name: uid,
      lastName: 'Test',
      courses: const [],
      role: 'User',
      createdAt: DateTime(2026),
      isActive: active,
    );

void main() {
  testWidgets('mostra solo utenti attivi non iscritti e forza aggiunta Admin',
      (tester) async {
    final existing = subscriber('existing');
    String? added;
    bool? forced;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddSubscriberDialog(
            courseId: 'course-1',
            courseName: 'Open',
            existingSubscribers: [existing],
            capacity: 10,
            loadUsersOperation: () async => [
              existing,
              subscriber('available'),
              subscriber('inactive', active: false),
            ],
            subscribeOperation: (courseId, userId, {force = false}) async {
              added = '$courseId:$userId';
              forced = force;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-subscriber-user-existing')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('add-subscriber-user-inactive')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('add-subscriber-user-available')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('add-subscriber-action-available')),
    );
    await tester.pumpAndSettle();
    expect(added, 'course-1:available');
    expect(forced, isTrue);
  });

  testWidgets('ricerca filtra per nome completo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddSubscriberDialog(
            courseId: 'course-1',
            courseName: 'Open',
            existingSubscribers: const [],
            capacity: 10,
            loadUsersOperation: () async => [
              subscriber('mario'),
              subscriber('luisa'),
            ],
            subscribeOperation: (_, __, {force = false}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-subscriber-search-field')),
      'luisa',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('add-subscriber-user-mario')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('add-subscriber-user-luisa')),
      findsOneWidget,
    );
  });
}
