import 'package:fitrope_app/types/fitrope_user.dart';

bool _within(DateTime value, DateTime start, DateTime end) =>
    !value.isBefore(start) && !value.isAfter(end);

/// Utenti attivi con almeno una scadenza legacy o multi-sub nei prossimi giorni.
/// Ogni utente compare una sola volta anche con più subscription in scadenza.
List<FitropeUser> usersWithSubscriptionsExpiringWithin(
  Iterable<FitropeUser> users, {
  int days = 30,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final limit = reference.add(Duration(days: days));
  return users.where((user) {
    if (!user.isActive) return false;
    final legacy = user.fineIscrizione?.toDate();
    if (legacy != null && _within(legacy, reference, limit)) return true;
    return user.activeSubscriptions.any((subscription) =>
        _within(subscription.endDate.toDate(), reference, limit));
  }).toList();
}

/// Record realmente privi di qualsiasi data di scadenza.
List<FitropeUser> usersWithoutSubscriptionEndDate(Iterable<FitropeUser> users) {
  return users
      .where((user) =>
          user.role != 'Admin' &&
          user.role != 'Trainer' &&
          user.fineIscrizione == null &&
          user.activeSubscriptions.isEmpty)
      .toList();
}
