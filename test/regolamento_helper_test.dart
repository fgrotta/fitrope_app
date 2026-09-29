import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/regolamento_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

/// Il dialog raccoglie la marca prima della callable (il gate vero è
/// server-side). La marca è write-once nelle rules: dopo un'accettazione il
/// dialog non deve ricomparire, anche se la pagina tiene una copia stantia
/// dell'utente e l'iscrizione che segue è fallita.
void main() {
  late FakeFirebaseFirestore db;
  final socio = simUser(uid: 'u1', role: 'User');

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(socio.uid).set(socio.toJson());
    store.dispatch(SetUserAction(socio));
  });

  tearDown(() => store.dispatch(SetUserAction(null)));

  /// Monta un bottone che chiama l'helper come fanno le pagine e ne registra
  /// il risultato.
  Future<List<bool>> montaPagina(WidgetTester tester, FitropeUser user) async {
    final risultati = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => risultati.add(
              await RegolamentoHelper.checkAndAcceptRegolamento(
                context,
                user,
                firestore: db,
              ),
            ),
            child: const Text('Iscriviti'),
          ),
        ),
      ),
    ));
    return risultati;
  }

  Future<Timestamp?> marcaSalvata() async =>
      (await db.collection('users').doc(socio.uid).get())
          .data()?['regolamentoAccettatoIl'] as Timestamp?;

  testWidgets('accettazione: salva la marca e aggiorna lo store',
      (tester) async {
    final risultati = await montaPagina(tester, socio);

    await tester.tap(find.text('Iscriviti'));
    await tester.pumpAndSettle();
    expect(find.text('Regolamento della Palestra'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();

    expect(risultati, [true]);
    expect(await marcaSalvata(), isNotNull);
    expect(store.state.user?.regolamentoAccettatoIl, isNotNull);
  });

  testWidgets('dopo l\'accettazione il dialog non ricompare (copia stantia)',
      (tester) async {
    final risultati = await montaPagina(tester, socio);

    await tester.tap(find.text('Iscriviti'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    final prima = await marcaSalvata();

    // Secondo tentativo con lo stesso `user` della pagina, ancora senza marca.
    await tester.tap(find.text('Iscriviti'));
    await tester.pumpAndSettle();

    expect(find.text('Regolamento della Palestra'), findsNothing);
    expect(risultati, [true, true]);
    expect(await marcaSalvata(), prima);
  });

  testWidgets('Annulla: nessuna scrittura e nessuna iscrizione',
      (tester) async {
    final risultati = await montaPagina(tester, socio);

    await tester.tap(find.text('Iscriviti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(risultati, [false]);
    expect(await marcaSalvata(), isNull);
    expect(store.state.user?.regolamentoAccettatoIl, isNull);
  });

  testWidgets('salvataggio fallito e marca assente: false con errore',
      (tester) async {
    // Documento inesistente: l'update fallisce e la rilettura non trova nulla.
    await db.collection('users').doc(socio.uid).delete();
    final risultati = await montaPagina(tester, socio);

    await tester.tap(find.text('Iscriviti'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();

    expect(risultati, [false]);
    expect(
      find.text(
          'Errore durante il salvataggio dell\'accettazione del regolamento'),
      findsOneWidget,
    );
  });
}
