import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/get_tipologia_iscrizione_label.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';

/// Una riga di scadenza: per V2 ce n'e' una per piano, per V1 una sola riga
/// legacy. Evita di comprimere arbitrariamente piu piani in una data "max".
class SubscriptionExpiry {
  final String label;
  final Timestamp? endDate;
  final bool legacy;
  const SubscriptionExpiry(this.label, this.endDate, {this.legacy = false});
}

List<SubscriptionExpiry> subscriptionExpiries(FitropeUser user) {
  if (user.subscriptionModelVersion >= 2) {
    return user.activeSubscriptions
        .map((UserSubscription s) => SubscriptionExpiry(
              getSubscriptionTitle(s),
              s.endDate,
            ))
        .toList()
      ..sort((a, b) => (a.endDate?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.endDate?.millisecondsSinceEpoch ?? 0));
  }
  return [
    SubscriptionExpiry(
      user.tipologiaIscrizione == null
          ? 'Piano legacy'
          : getTipologiaIscrizioneLabel(user.tipologiaIscrizione!),
      user.fineIscrizione,
      legacy: true,
    )
  ];
}

List<SubscriptionExpiry> subscriptionsExpiringInNext30Days(
  FitropeUser user, {
  DateTime? now,
}) {
  final start = now ?? DateTime.now();
  final end = start.add(const Duration(days: 30));
  return subscriptionExpiries(user).where((expiry) {
    final date = expiry.endDate?.toDate();
    return date != null && date.isAfter(start) && !date.isAfter(end);
  }).toList();
}

int countSubscriptionsExpiringInNext30Days(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) {
  return users.fold<int>(
    0,
    (total, user) =>
        total + subscriptionsExpiringInNext30Days(user, now: now).length,
  );
}

bool hasNoActiveSubscription(FitropeUser user) {
  return user.subscriptionModelVersion >= 2
      ? user.activeSubscriptions.isEmpty
      : user.fineIscrizione == null;
}

bool hasSubscriptionExpiringInNext30Days(FitropeUser user, {DateTime? now}) {
  return subscriptionsExpiringInNext30Days(user, now: now).isNotEmpty;
}
