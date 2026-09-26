import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';

/// `RefreshManager` è un singleton: i listener sono State di pagine e card che
/// si registrano in initState e si tolgono in dispose. Una notifica non deve
/// dipendere da cosa fanno i listener mentre la ricevono.
void main() {
  final manager = RefreshManager();

  setUp(manager.clearListeners);
  tearDown(manager.clearListeners);

  test('un listener che si rimuove durante la notifica non ferma gli altri',
      () {
    final calls = <String>[];
    late void Function() selfRemoving;
    selfRemoving = () {
      calls.add('a');
      manager.removeListener(selfRemoving);
    };
    manager.addListener(selfRemoving);
    manager.addListener(() => calls.add('b'));

    manager.notifyRefresh();

    expect(calls, ['a', 'b']);
    expect(manager.listenerCount, 1);
  });

  test('un listener aggiunto durante la notifica parte dal giro successivo',
      () {
    var late = 0;
    manager.addListener(() => manager.addListener(() => late++));

    manager.notifyRefresh();
    expect(late, 0);
    expect(manager.listenerCount, 2);
  });

  test('un listener che lancia non ferma gli altri', () {
    var called = false;
    manager.addListener(() => throw StateError('boom'));
    manager.addListener(() => called = true);

    manager.notifyRefresh();

    expect(called, isTrue);
  });

  test('un listener rimosso da un altro durante il giro non viene chiamato',
      () {
    var removedCalled = false;
    void removed() => removedCalled = true;
    manager.addListener(() => manager.removeListener(removed));
    manager.addListener(removed);

    manager.notifyRefresh();

    expect(removedCalled, isFalse);
  });

  test('in lib/ ci si aggancia solo con RefreshListenersMixin', () {
    // add/remove a mano obbligano a ricalcolare in dispose cosa togliere: è
    // così che HomePage lasciava listener agganciati a uno State morto.
    final direct = RegExp(r'RefreshManager\(\)\s*\.\s*(add|remove)Listener');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('refresh_manager.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (direct.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Usa `with RefreshListenersMixin` + `listenToRefresh`.');
  });
}
