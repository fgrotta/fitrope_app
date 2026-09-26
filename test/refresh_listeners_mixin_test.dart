import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';

/// Chi si aggancia a `RefreshManager` lo fa con `listenToRefresh`, e il mixin
/// toglie in dispose ESATTAMENTE ciò che è stato aggiunto. Prima ogni State
/// ricalcolava in dispose cosa togliere (es. HomePage da `user.role`, che
/// `refreshCourses` può cambiare copiando lo store): un ruolo diverso tra
/// initState e dispose lasciava listener agganciati a uno State morto.
class _Probe extends StatefulWidget {
  const _Probe({required this.role, required this.calls});
  final String role;
  final List<String> calls;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with RefreshListenersMixin<_Probe> {
  late String role = widget.role;

  @override
  void initState() {
    super.initState();
    if (role == 'Admin') {
      listenToRefresh(() => widget.calls.add('admin-a'));
      listenToRefresh(() => widget.calls.add('admin-b'));
    } else {
      listenToRefresh(() => widget.calls.add('user'));
    }
    // Come HomePage.refreshCourses che copia lo store: il ruolo cambia dopo
    // la registrazione.
    role = role == 'Admin' ? 'User' : 'Admin';
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  final manager = RefreshManager();
  setUp(manager.clearListeners);

  testWidgets('dispose toglie tutti e soli i listener registrati',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_Probe(role: 'Admin', calls: calls));
    expect(manager.listenerCount, 2);

    manager.notifyRefresh();
    expect(calls, ['admin-a', 'admin-b']);

    await tester.pumpWidget(const SizedBox());
    expect(manager.listenerCount, 0);

    manager.notifyRefresh();
    expect(calls, ['admin-a', 'admin-b']);
  });

  testWidgets('non tocca i listener di altri State', (tester) async {
    var other = 0;
    void otherListener() => other++;
    manager.addListener(otherListener);

    await tester.pumpWidget(const _Probe(role: 'User', calls: <String>[]));
    expect(manager.listenerCount, 2);
    await tester.pumpWidget(const SizedBox());
    expect(manager.listenerCount, 1);

    manager.notifyRefresh();
    expect(other, 1);
  });
}
