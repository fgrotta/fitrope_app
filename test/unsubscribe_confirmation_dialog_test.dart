import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dialog "Conferma Disiscrizione" (disdetta tardiva): i test di
/// `canUnsubscribe` coprono QUANDO serve la conferma, qui si verifica COSA vede
/// l'utente e che l'esito del dialog guidi davvero il flusso.
void main() {
  Course course(
    String uid,
    DateTime start, {
    List<String> tags = const [],
    int capacity = 20,
    int subscribed = 5,
  }) =>
      Course(
        id: uid,
        uid: uid,
        name: 'Corso $uid',
        startDate: Timestamp.fromDate(start),
        endDate: Timestamp.fromDate(start.add(const Duration(hours: 1))),
        capacity: capacity,
        subscribed: subscribed,
        tags: tags,
      );

  /// Monta un'app vuota e restituisce un context sotto al Navigator.
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return const Scaffold();
      }),
    ));
    return captured;
  }

  Future<Future<bool>> openDialog(
    WidgetTester tester,
    Course target, {
    bool isTemporalSubscription = false,
    String courseTypeLabel = 'Open',
    int recoveryCount = 1,
  }) async {
    final context = await pumpHost(tester);
    final result = CourseUnsubscribeHelper.showConfirmationDialog(
      context,
      target,
      isTemporalSubscription: isTemporalSubscription,
      courseTypeLabel: courseTypeLabel,
      recoveryCount: recoveryCount,
    );
    await tester.pumpAndSettle();
    return result;
  }

  Color? colorOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style?.color;

  group('showConfirmationDialog: contenuto', () {
    testWidgets('data e ora del corso in orario italiano (ora legale)',
        (tester) async {
      // 18:30 UTC del 23/9 = 20:30 CEST.
      await openDialog(
          tester, course('c-1', DateTime.utc(2026, 9, 23, 18, 30)));

      expect(find.text('Conferma Disiscrizione'), findsNWidgets(2));
      expect(
        find.text('Stai per disiscriverti dal corso "Corso c-1" '
            'del 23/9/2026 alle 20:30'),
        findsOneWidget,
      );
      expect(find.text('Sei sicuro di voler procedere?'), findsOneWidget);
    });

    testWidgets('data e ora del corso in orario italiano (ora solare)',
        (tester) async {
      // 18:30 UTC del 15/1 = 19:30 CET.
      await openDialog(
          tester, course('c-1', DateTime.utc(2026, 1, 15, 18, 30)));

      expect(find.textContaining('del 15/1/2026 alle 19:30'), findsOneWidget);
    });

    testWidgets('pacchetto/prova: soglia 8 ore e tipologia nel messaggio',
        (tester) async {
      await openDialog(
        tester,
        course('c-1', DateTime.utc(2026, 9, 23, 18, 30)),
        courseTypeLabel: 'Personal Trainer',
      );

      final warning = find.text(
        'ATTENZIONE: mancano meno di 8 ore all\'inizio del corso. '
        'Per non perdere la lezione devi iscriverti a un altro corso '
        'Personal Trainer di oggi entro le 23:59.',
      );
      expect(warning, findsOneWidget);
      expect(colorOf(tester, warning), Colors.red);
    });

    testWidgets('abbonamento temporale: soglia 4 ore', (tester) async {
      await openDialog(
        tester,
        course('c-1', DateTime.utc(2026, 9, 23, 18, 30)),
        isTemporalSubscription: true,
      );

      expect(find.textContaining('mancano meno di 4 ore'), findsOneWidget);
      expect(find.textContaining('mancano meno di 8 ore'), findsNothing);
    });

    testWidgets('nessun corso di recupero: avviso di perdita in rosso',
        (tester) async {
      await openDialog(
        tester,
        course('c-1', DateTime.utc(2026, 9, 23, 18, 30)),
        recoveryCount: 0,
      );

      final message = find.text('Oggi non ci sono altri corsi Open con posti '
          'liberi: confermando perderai la lezione.');
      expect(message, findsOneWidget);
      expect(colorOf(tester, message), Colors.red);
    });

    testWidgets('un corso di recupero: singolare, testo non di allarme',
        (tester) async {
      await openDialog(
        tester,
        course('c-1', DateTime.utc(2026, 9, 23, 18, 30)),
        courseTypeLabel: 'Personal Trainer',
        recoveryCount: 1,
      );

      final message = find
          .text('Oggi c\'è ancora 1 corso Personal Trainer con posti liberi.');
      expect(message, findsOneWidget);
      expect(colorOf(tester, message), Colors.black87);
    });

    testWidgets('più corsi di recupero: plurale', (tester) async {
      await openDialog(
        tester,
        course('c-1', DateTime.utc(2026, 9, 23, 18, 30)),
        recoveryCount: 3,
      );

      expect(
        find.text('Oggi ci sono ancora 3 corsi Open con posti liberi.'),
        findsOneWidget,
      );
    });
  });

  group('showConfirmationDialog: esito', () {
    testWidgets('Annulla → false e il dialog si chiude', (tester) async {
      final result = await openDialog(
          tester, course('c-1', DateTime.utc(2026, 9, 23, 18, 30)));

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Conferma Disiscrizione → true', (tester) async {
      final result = await openDialog(
          tester, course('c-1', DateTime.utc(2026, 9, 23, 18, 30)));

      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Conferma Disiscrizione'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('tap fuori dal dialog non lo chiude (scelta obbligata)',
        (tester) async {
      await openDialog(
          tester, course('c-1', DateTime.utc(2026, 9, 23, 18, 30)));

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  /// Flusso reale: `handleUnsubscribe` decide via `canUnsubscribe`, conta il
  /// recupero sul catalogo dello store e passa i valori al dialog. Si esce
  /// sempre con "Annulla", così nessuna callable viene invocata.
  group('handleUnsubscribe → dialog', () {
    // I corsi di recupero partono allo STESSO istante del corso disdetto:
    // stessa giornata per costruzione, qualunque sia l'ora in cui gira il test.
    final start = DateTime.now().add(const Duration(hours: 2));

    UserSubscription sub({
      required SubscriptionFamily family,
      required BillingMode billingMode,
      required Set<String> courseTypeTags,
    }) =>
        UserSubscription(
          id: 'sub-1',
          planKey: 'test-plan',
          family: family,
          billingMode: billingMode,
          courseTypeTags: courseTypeTags,
          weeklyFrequency: billingMode == BillingMode.FREQUENCY ? 2 : null,
          remainingEntries: billingMode == BillingMode.ENTRIES ? 5 : null,
          startDate: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 10))),
          endDate:
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        );

    FitropeUser user({
      required List<String> courses,
      List<UserSubscription> subscriptions = const [],
      TipologiaIscrizione? tipologia,
    }) =>
        FitropeUser(
          uid: 'u1',
          email: 'u1@example.com',
          name: 'Test',
          lastName: 'User',
          courses: courses,
          tipologiaIscrizione: tipologia,
          entrateDisponibili: tipologia == null ? null : 1,
          fineIscrizione:
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          role: 'User',
          createdAt: DateTime.now(),
          activeSubscriptions: subscriptions,
        );

    Future<void> expectDialogThenCancel(
      WidgetTester tester,
      Course target,
      FitropeUser u, {
      required List<String> expectedTexts,
    }) async {
      final context = await pumpHost(tester);
      final result =
          CourseUnsubscribeHelper.handleUnsubscribe(target, u, context);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      for (final text in expectedTexts) {
        expect(find.textContaining(text), findsOneWidget, reason: text);
      }

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    }

    testWidgets(
        'PT a ingressi a 2h (scenario dello screenshot): 8 ore, '
        '1 corso Personal Trainer di recupero', (tester) async {
      final target = course('pt-1', start, tags: ['Personal Trainer']);
      store.dispatch(SetAllCoursesAction([
        target,
        // Unico recupero valido.
        course('pt-2', start, tags: ['Personal Trainer']),
        // Esclusi: pieno, altra tipologia, altro giorno.
        course('pt-full', start,
            tags: ['Personal Trainer'], capacity: 1, subscribed: 1),
        course('open-1', start),
        course('pt-tomorrow', start.add(const Duration(days: 1)),
            tags: ['Personal Trainer']),
      ]));

      await expectDialogThenCancel(
        tester,
        target,
        user(courses: [
          'pt-1'
        ], subscriptions: [
          sub(
            family: SubscriptionFamily.PT,
            billingMode: BillingMode.ENTRIES,
            courseTypeTags: const {'Personal Trainer'},
          ),
        ]),
        expectedTexts: [
          'mancano meno di 8 ore',
          'altro corso Personal Trainer di oggi entro le 23:59',
          'Oggi c\'è ancora 1 corso Personal Trainer con posti liberi.',
        ],
      );
    });

    testWidgets(
        'Open a frequenza a 2h, corso senza tag: 4 ore, "Open", '
        'nessun recupero', (tester) async {
      final target = course('open-1', start);
      store.dispatch(SetAllCoursesAction([
        target,
        course('pt-1', start, tags: ['Personal Trainer']),
      ]));

      await expectDialogThenCancel(
        tester,
        target,
        user(courses: [
          'open-1'
        ], subscriptions: [
          sub(
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            courseTypeTags: const {'Open'},
          ),
        ]),
        expectedTexts: [
          'mancano meno di 4 ore',
          'altro corso Open di oggi',
          'Oggi non ci sono altri corsi Open con posti liberi',
        ],
      );
    });

    testWidgets('legacy ABBONAMENTO_PROVA a 2h: soglia 8 ore', (tester) async {
      final target = course('open-1', start);
      store.dispatch(SetAllCoursesAction([
        target,
        course('open-2', start),
        course('open-3', start),
      ]));

      await expectDialogThenCancel(
        tester,
        target,
        user(
          courses: ['open-1'],
          tipologia: TipologiaIscrizione.ABBONAMENTO_PROVA,
        ),
        expectedTexts: [
          'mancano meno di 8 ore',
          'Oggi ci sono ancora 2 corsi Open con posti liberi.',
        ],
      );
    });
  });
}
