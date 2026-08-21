import 'package:fitrope_app/api/authentication/create_user.dart';
import 'package:fitrope_app/pages/protected/create_user_page.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default e validazioni base della creazione utente',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateUserPage(currentUserRole: 'Admin')),
    );

    expect(find.byKey(const Key('create-user-role-dropdown')), findsOneWidget);
    final entries = tester.widget<TextFormField>(
      find.byKey(const Key('create-user-entries-field')),
    );
    final weekly = tester.widget<TextFormField>(
      find.byKey(const Key('create-user-weekly-entries-field')),
    );
    expect(entries.controller!.text, '1');
    expect(weekly.controller!.text, '0');

    final submit = find.byKey(const Key('create-user-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Inserisci il nome'), findsOneWidget);
    expect(find.text('Inserisci il cognome'), findsOneWidget);
  });

  testWidgets('il dropdown ruolo non è disponibile al Trainer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateUserPage(currentUserRole: 'Trainer')),
    );
    expect(find.byKey(const Key('create-user-role-dropdown')), findsNothing);
  });

  testWidgets('valida email, password e telefono opzionali', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateUserPage(currentUserRole: 'Admin')),
    );
    await tester.enterText(
      find.byKey(const Key('create-user-name-field')),
      'Nome',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-last-name-field')),
      'Cognome',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-email-field')),
      'non-valida',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-password-field')),
      '123',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-phone-field')),
      '12345',
    );
    final submit = find.byKey(const Key('create-user-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text("Inserisci un'email valida"), findsOneWidget);
    expect(
      find.text('La password deve essere di almeno 6 caratteri'),
      findsOneWidget,
    );
    expect(
      find.text('Il numero di telefono deve contenere esattamente 10 cifre'),
      findsOneWidget,
    );
  });

  testWidgets(
      'senza email inoltra password ma richiede un utente senza accesso',
      (tester) async {
    final captured = <String, Object?>{};
    await tester.pumpWidget(
      MaterialApp(
        home: CreateUserPage(
          currentUserRole: 'Admin',
          createUserOperation: ({
            String? email,
            String? password,
            required String name,
            required String lastName,
            required String role,
            TipologiaIscrizione? tipologiaIscrizione,
            int? entrateDisponibili,
            int? entrateSettimanali,
            DateTime? fineIscrizione,
            required bool isAnonymous,
            String? numeroTelefono,
            List<String>? tipologiaCorsoTags,
          }) async {
            captured.addAll({
              'email': email,
              'password': password,
              'role': role,
              'tags': List<String>.from(tipologiaCorsoTags ?? []),
            });
            return CreateUserResponse(
              user: FitropeUser(
                uid: 'generated',
                email: '',
                name: name,
                lastName: lastName,
                courses: const [],
                role: role,
                createdAt: DateTime(2026),
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('create-user-name-field')),
      'Senza',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-last-name-field')),
      'Accesso',
    );
    await tester.enterText(
      find.byKey(const Key('create-user-password-field')),
      'password-accettata',
    );
    final submit = find.byKey(const Key('create-user-submit-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(captured['email'], isNull);
    expect(captured['password'], 'password-accettata');
    expect(captured['role'], 'User');
    expect(captured['tags'], ['Open']);
  });
}
