import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:fitrope_app/utils/user_cache_manager.dart';

/// `invalidateAllUserCaches` è l'unico punto che notifica il refresh dopo una
/// mutazione utente: prima le due `invalidateUsersWithExpiring*Cache` notificavano
/// ciascuna per conto suo, e al resume `Protected` aggiungeva una terza notifica
/// (ogni `CoursePreviewCard` rifaceva la sua query tre volte).
void main() {
  late int notifications;
  void listener() => notifications++;

  setUp(() {
    notifications = 0;
    RefreshManager().addListener(listener);
  });

  tearDown(() => RefreshManager().removeListener(listener));

  test('notifica una sola volta', () {
    invalidateAllUserCaches();
    expect(notifications, 1);
  });

  test('con notify: false non notifica (ci pensa il chiamante)', () {
    invalidateAllUserCaches(notify: false);
    expect(notifications, 0);
  });
}
