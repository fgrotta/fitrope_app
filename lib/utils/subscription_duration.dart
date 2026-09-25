import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/subscription_expiry.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Durata di un abbonamento come la legge la dashboard admin. L'ordine
/// dell'enum è l'ordine di visualizzazione.
enum SubscriptionDuration {
  prova('Abbonamento Prova'),
  mensile('Abbonamento mensile'),
  trimestrale('Abbonamento trimestrale'),
  semestrale('Abbonamento semestrale'),
  annuale('Abbonamento annuale');

  final String label;

  const SubscriptionDuration(this.label);
}

/// Durata dal catalogo: i piani a giorni sono la Prova, gli altri si
/// distinguono per mesi. `null` solo per un piano fuori catalogo o una durata
/// che la dashboard non conosce (difensivo: `UserSubscription.fromJson`
/// rifiuta già i planKey sconosciuti).
SubscriptionDuration? subscriptionDurationOf(UserSubscription s) {
  final plan = SubscriptionPlans.byKey(s.planKey);
  if (plan == null) return null;
  if (plan.durationDays != null) return SubscriptionDuration.prova;
  switch (plan.durationMonths) {
    case 1:
      return SubscriptionDuration.mensile;
    case 3:
      return SubscriptionDuration.trimestrale;
    case 6:
      return SubscriptionDuration.semestrale;
    case 12:
      return SubscriptionDuration.annuale;
  }
  return null;
}

/// Soci per durata degli abbonamenti vivi, con tutte le durate presenti anche
/// a zero e in ordine fisso. Conta **soci**, non abbonamenti: chi ha due
/// mensili (es. Open + PT) compare una volta sola, chi ha durate diverse
/// compare in ciascuna voce.
List<MapEntry<SubscriptionDuration, List<FitropeUser>>>
    usersBySubscriptionDuration(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) =>
        _groupUsers(
          users,
          SubscriptionDuration.values,
          subscriptionDurationOf,
          (u) => liveSubscriptions(u.activeSubscriptions, now: now),
        );

/// Soci per durata degli abbonamenti che scadono nei prossimi 30 giorni
/// ([expiresInNext30Days], la stessa finestra del KPI "Abbonamenti in
/// scadenza"). Conta la durata dell'abbonamento che scade, non quella degli
/// altri abbonamenti del socio. Solo modello V2: un piano legacy V1 non ha una
/// durata di catalogo e resta fuori dalla ripartizione.
List<MapEntry<SubscriptionDuration, List<FitropeUser>>>
    usersByExpiringSubscriptionDuration(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  return _groupUsers(
    users,
    SubscriptionDuration.values,
    subscriptionDurationOf,
    (u) => u.activeSubscriptions
        .where((s) => expiresInNext30Days(s.endDate.toDate(), ref)),
  );
}

/// Soci per famiglia degli abbonamenti vivi, in ordine fisso
/// [SubscriptionFamily.values] e con le famiglie a zero incluse. Stessa
/// semantica di [usersBySubscriptionDuration]: il numero coincide con le righe
/// del drawer che si apre al tap.
List<MapEntry<SubscriptionFamily, List<FitropeUser>>> usersBySubscriptionFamily(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) =>
    _groupUsers(
      users,
      SubscriptionFamily.values,
      (s) => s.family,
      (u) => liveSubscriptions(u.activeSubscriptions, now: now),
    );

List<MapEntry<K, List<FitropeUser>>> _groupUsers<K>(
  Iterable<FitropeUser> users,
  List<K> keys,
  K? Function(UserSubscription s) keyOf,
  Iterable<UserSubscription> Function(FitropeUser u) subscriptionsOf,
) {
  final byKey = {for (final k in keys) k: <FitropeUser>[]};
  for (final u in users) {
    final userKeys = subscriptionsOf(u).map(keyOf).whereType<K>().toSet();
    for (final k in userKeys) {
      byKey[k]?.add(u);
    }
  }
  return [for (final k in keys) MapEntry(k, byKey[k]!)];
}

/// Soci con almeno un abbonamento a ingressi vivo e media dei residui su
/// quegli abbonamenti (non sui soci). Solo modello V2: il saldo legacy
/// `entrateDisponibili` non entra nel calcolo.
(List<FitropeUser> users, double average) averageRemainingEntries(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) {
  final withEntries = <FitropeUser>[];
  final balances = <int>[];
  for (final u in users) {
    final entrySubscriptions =
        liveSubscriptions(u.activeSubscriptions, now: now)
            .where((s) => s.billingMode == BillingMode.ENTRIES)
            .toList();
    if (entrySubscriptions.isEmpty) continue;
    withEntries.add(u);
    balances.addAll(entrySubscriptions.map((s) => s.remainingEntries ?? 0));
  }
  final average = balances.isEmpty
      ? 0.0
      : balances.reduce((a, b) => a + b) / balances.length;
  return (withEntries, average);
}
