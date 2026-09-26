import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/pages/protected/admin_home_sections.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';

/// Le sezioni admin della Home sono una libreria deferred con i propri
/// listener su `RefreshManager`. Il test fissa il contratto del refresh:
/// quattro letture all'avvio, un giro completo a ogni notifica globale, solo
/// certificati e abbonamenti sul segnale della Home, e nessun listener
/// residuo dopo il dispose.
class _CountingListenable extends ChangeNotifier {
  int adds = 0;
  int removes = 0;

  @override
  void addListener(VoidCallback listener) {
    adds++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removes++;
    super.removeListener(listener);
  }

  void ping() => notifyListeners();
}

void main() {
  final manager = RefreshManager();
  late Map<String, int> calls;
  late AdminHomeLoaders loaders;

  setUp(() {
    manager.clearListeners();
    calls = {'cert': 0, 'abb': 0, 'all': 0};
    loaders = AdminHomeLoaders(
      expiringCertificates: () async {
        calls['cert'] = calls['cert']! + 1;
        return <FitropeUser>[];
      },
      expiringSubscriptions: () async {
        calls['abb'] = calls['abb']! + 1;
        return <FitropeUser>[];
      },
      allUsers: () async {
        calls['all'] = calls['all']! + 1;
        return <FitropeUser>[];
      },
    );
  });

  Future<void> pump(WidgetTester tester, Listenable signal,
      {Size size = const Size(1200, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminHomeSections(
            allCourses: const [],
            refreshSignal: signal,
            loaders: loaders,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('avvio: quattro letture e quattro listener', (tester) async {
    await pump(tester, _CountingListenable());

    // Lezioni di prova e regolamento leggono entrambe la lista utenti.
    expect(calls, {'cert': 1, 'abb': 1, 'all': 2});
    expect(manager.listenerCount, 4);
  });

  testWidgets('una notifica globale rilegge tutto, una volta', (tester) async {
    await pump(tester, _CountingListenable());

    manager.notifyRefresh();
    await tester.pumpAndSettle();

    expect(calls, {'cert': 2, 'abb': 2, 'all': 4});
  });

  testWidgets('il segnale della Home rilegge solo certificati e abbonamenti',
      (tester) async {
    final signal = _CountingListenable();
    await pump(tester, signal);

    signal.ping();
    await tester.pumpAndSettle();

    expect(calls, {'cert': 2, 'abb': 2, 'all': 2});
  });

  testWidgets('dispose: nessun listener residuo, nessuna lettura dopo',
      (tester) async {
    final signal = _CountingListenable();
    await pump(tester, signal);

    await tester.pumpWidget(const SizedBox());
    expect(manager.listenerCount, 0);
    expect(signal.removes, signal.adds);

    manager.notifyRefresh();
    signal.ping();
    await tester.pump();
    expect(calls, {'cert': 1, 'abb': 1, 'all': 2});
  });

  testWidgets('desktop: righe comprimibili con i titoli delle sezioni',
      (tester) async {
    await pump(tester, _CountingListenable());

    expect(find.text('Scadenze'), findsOneWidget);
    expect(find.text('Lezioni di prova'), findsOneWidget);
    expect(find.text('Regolamento'), findsOneWidget);
  });

  testWidgets('mobile: niente righe comprimibili', (tester) async {
    await pump(tester, _CountingListenable(), size: const Size(400, 900));

    expect(find.text('Scadenze'), findsNothing);
  });
}
