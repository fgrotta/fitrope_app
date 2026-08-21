import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FitropeUser preferenceUser({bool email = true, bool push = true}) =>
    FitropeUser(
      uid: 'self',
      email: 'self@example.com',
      name: 'Self',
      lastName: 'User',
      courses: const [],
      role: 'User',
      createdAt: DateTime(2026),
      emailNotificationsEnabled: email,
      pushNotificationsEnabled: push,
    );

Future<void> pumpPreferences(
  WidgetTester tester, {
  required FitropeUser user,
  required UpdateUserOperation update,
  Future<void> Function(bool)? setPush,
  Future<void> Function(bool)? syncPush,
}) async {
  store.dispatch(SetUserAction(user));
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: UserDetailPage(
        user: user,
        openInEditMode: true,
        loadCoursesOperation: () async => [],
        updateUserOperation: update,
        setPushEnabledOperation: setPush ?? (_) async {},
        hasPushPermissionOperation: () async => true,
        canRequestPushPermissionOperation: () async => true,
        syncPushPreferenceOperation: syncPush ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('salva la preferenza email self nel payload diff-based',
      (tester) async {
    bool? capturedEmail;
    await pumpPreferences(
      tester,
      user: preferenceUser(),
      update: ({
        required original,
        required name,
        required lastName,
        required role,
        tipologiaIscrizione,
        entrateDisponibili,
        entrateSettimanali,
        fineIscrizione,
        isActive,
        isAnonymous,
        certificatoScadenza,
        numeroTelefono,
        tipologiaCorsoTags,
        emailNotificationsEnabled,
        pushNotificationsEnabled,
      }) async {
        capturedEmail = emailNotificationsEnabled;
      },
    );
    final emailSwitch = find.byKey(const Key('user-notification-email-switch'));
    tester.widget<Switch>(emailSwitch).onChanged!(false);
    await tester.pump();
    tester
        .widget<IconButton>(find.byKey(const Key('user-detail-save-button')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(capturedEmail, isFalse);
  });

  testWidgets('su errore Firestore ripristina la preferenza push precedente',
      (tester) async {
    final applied = <bool>[];
    final rolledBack = <bool>[];
    await pumpPreferences(
      tester,
      user: preferenceUser(push: true),
      setPush: (enabled) async => applied.add(enabled),
      syncPush: (enabled) async => rolledBack.add(enabled),
      update: ({
        required original,
        required name,
        required lastName,
        required role,
        tipologiaIscrizione,
        entrateDisponibili,
        entrateSettimanali,
        fineIscrizione,
        isActive,
        isAnonymous,
        certificatoScadenza,
        numeroTelefono,
        tipologiaCorsoTags,
        emailNotificationsEnabled,
        pushNotificationsEnabled,
      }) async {
        throw Exception('write failed');
      },
    );
    final pushSwitch = find.byKey(const Key('user-notification-push-switch'));
    tester.widget<Switch>(pushSwitch).onChanged!(false);
    await tester.pump();
    tester
        .widget<IconButton>(find.byKey(const Key('user-detail-save-button')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(applied, [false]);
    expect(rolledBack, [true]);
    expect(find.text("Errore durante l'aggiornamento"), findsOneWidget);
  });
}
