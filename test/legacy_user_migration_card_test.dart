import 'package:fitrope_app/components/legacy_user_migration_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double width = 1200}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(body: child),
      ),
    );

Map<String, dynamic> result(
  String status, {
  Map<String, dynamic> normalization = const {},
}) =>
    <String, dynamic>{
      'status': status,
      'expectedFingerprint': 'fingerprint',
      'reasonDetail': 'conflitto esistente',
      'legacy': <String, dynamic>{
        'tipologiaIscrizione': 'ABBONAMENTO_MENSILE',
        'entrateSettimanali': 2,
        'fineIscrizione': DateTime(2026, 12, 31).millisecondsSinceEpoch,
      },
      'normalization': normalization,
      if (status == 'AUTO_CONVERTIBLE')
        'target': <String, dynamic>{'planKey': 'open_2x_1m'},
    };

void main() {
  testWidgets('il gate richiede Admin anche su mobile', (tester) async {
    final values = <bool>[];
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            values.add(shouldShowLegacyUserMigration(context, 'Admin'));
            values.add(shouldShowLegacyUserMigration(context, 'Trainer'));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(values, [true, false]);

    values.clear();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            values.add(shouldShowLegacyUserMigration(context, 'Admin'));
            return const SizedBox();
          },
        ),
        width: 700,
      ),
    );
    expect(values, [true]);
  });

  testWidgets('mostra anteprima automatica e scompare dopo il successo',
      (tester) async {
    var migrated = false;
    await tester.pumpWidget(
      host(
        LegacyUserMigrationCard(
          userId: 'u1',
          preview: (_) async => result('AUTO_CONVERTIBLE'),
          migrateAuto: (_, __) async => <String, dynamic>{'status': 'MIGRATED'},
          onMigrated: () => migrated = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-user-migration-card')), findsOneWidget);
    expect(find.textContaining('open_2x_1m'), findsOneWidget);

    await tester.tap(find.byKey(const Key('legacy-migration-auto')));
    await tester.pumpAndSettle();
    expect(find.text('Conferma migrazione'), findsOneWidget);
    await tester.tap(find.text('Migra'));
    await tester.pumpAndSettle();
    expect(migrated, isTrue);
    expect(find.byKey(const Key('legacy-user-migration-card')), findsNothing);
  });

  testWidgets('CONFLICT resta in sola lettura', (tester) async {
    await tester.pumpWidget(
      host(
        LegacyUserMigrationCard(
          userId: 'u1',
          preview: (_) async => result('CONFLICT'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('conflitto esistente'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('un profilo auto convertibile può scegliere un piano guidato',
      (tester) async {
    await tester.pumpWidget(
      host(
        LegacyUserMigrationCard(
          userId: 'u1',
          preview: (_) async => result(
            'AUTO_CONVERTIBLE',
            normalization: <String, dynamic>{
              'tipologiaCorsoTags': ['Open']
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('legacy-migration-guided-choice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-migration-plan')), findsOneWidget);
    expect(find.text('Migra con piano scelto'), findsOneWidget);
  });

  testWidgets('MIGRATED e NOT_APPLICABLE non renderizzano la card',
      (tester) async {
    for (final status in ['MIGRATED', 'NOT_APPLICABLE']) {
      await tester.pumpWidget(
        host(
          LegacyUserMigrationCard(
            key: ValueKey(status),
            userId: 'u1',
            preview: (_) async => result(status),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legacy-user-migration-card')), findsNothing);
    }
  });

  testWidgets('offre NORMALIZE anche per profili esclusi o già migrati',
      (tester) async {
    for (final status in ['MIGRATED', 'NOT_APPLICABLE']) {
      var normalized = false;
      await tester.pumpWidget(
        host(
          LegacyUserMigrationCard(
            key: ValueKey('normalizable-$status'),
            userId: 'u1',
            preview: (_) async => result(
              status,
              normalization: <String, dynamic>{'role': 'User'},
            ),
            normalize: (_, __) async {
              normalized = true;
              return <String, dynamic>{'status': 'NORMALIZED'};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('legacy-migration-normalize')), findsOneWidget);
      await tester.tap(find.byKey(const Key('legacy-migration-normalize')));
      await tester.pumpAndSettle();
      expect(normalized, isTrue);
    }
  });
}
